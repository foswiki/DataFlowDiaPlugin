# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/SimpleStore.pm#3 $

# Copyright 2015 Applied Research Laboratories, the University of
# Texas at Austin.
#
#    This file is part of DataFlowDiaPlugin.
#
#    DataFlowDiaPlugin is free software: you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation, either version 3 of
#    the License, or (at your option) any later version.
#
#    DataFlowDiaPlugin is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#    See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with DataFlowDiaPlugin.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: John Knutson
#
# Provide a mechanism for documenting the interconnections between processes.

=begin TML

---+ package Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore

Provide a very simple yet common way for storing (internally) data
used by DataFlowDiaPlugin.  This is NOT the same as XMLStoreContrib,
though it does borrow some of that code.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use XML::LibXML;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :graphviz :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes);
use Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection;
use Foswiki::Func;
use Fcntl qw/:flock :seek/;    # import LOCK_* and SEEK_* constants

my $entityTypeRegex = qr/(PROC|DATA|LOCALE|TRANSPORT|GROUP)/;




################################
# CONSTRUCTORS
################################


# Create a new Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore for
# the class $storeClass.
#
# $param[in] $class The name of the class being instantiated.
# $param[in] $storeClass a class derived from ::Entity to parse the
#   XML::LibXML::Elements
# $param[in] $rootName the document node name for the XML.
# $param[in] $nodeName the XML node name for nodes to be processed by
#   $storeClass.
# $param[in] $entityType the name of the entity (not necessarily the
#   same as $storeClass).
# $param[in] $docManager Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (for building cross-references).
sub new {
    my ($class,
        $storeClass,
        $rootName,
        $nodeName,
        $entityType,
        $docManager) = @_;
    my $self = {
        'rootName'    => $rootName,   # see sub docs
        'nodeName'    => $nodeName,   # see sub docs
        'entityClass' => $storeClass, # see sub docs
        'entityType'  => $entityType, # see sub docs
        'hash'        => {},          # hash mapping entity ID to entity ref
        'updated'     => {},          # hash mapping entity ID to entity ref
        'topicxml'    => [],          # array of stored entities for this topic
        'topicmacro'  => [],          # array of defined entities for this topic
        'docMgr'      => $docManager, # parent DocManager instance
        'searchdoc'   => undef,       # XML::LibXML::Document for searching
    };
    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################


# Pre-process entity definition macros.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return The original macro text (which will be rendered "properly"
#   on a second pass of the plug-in).
sub addMacroData {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;
    return macroError(
        "Missing required id parameter in " . $self->entityType() . " macro")
        unless defined($macroAttrs->{'id'});
    # get or create the desired entity
    my $entity = $self->getEntity($web, $macroAttrs->{'id'});
    # keep a copy of the XML as it should appear on disk to check for changes
    my $origXML = $entity->toXML($self->nodeName(), 0);
    # check to make sure the entity hasn't already been defined somewhere else
    if ($entity->isDefined() &&
        ($entity->topic() ne $topic)) {
        return macroError(
            $self->entityType() . " Entity \"<nop>" . $entity->id()
            . "\" is already defined here: " . $entity->getWikiLink()
            . ".  Please remove one of the definitions.");
    }
    # update the entity from macro parameters
    $entity->fromMacro($web, $topic, $macroAttrs);
    my $newXML = $entity->toXML($self->nodeName(), 0);
    push @{ $self->{'topicmacro'} }, $web . "." . $macroAttrs->{'id'};
    $self->markChanged($entity)
        if ($origXML->toString(0) ne $newXML->toString(0));
    # return the original macro text for render-stage processing
    return $macroAttrs->{'_ORIG'};
}


################################
# XML PROCESSING
################################


# Create and return a new XML::LibXML::Document representing the data
# in this SimpleStore.
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# $param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set =$inclInh= to a
#   non-zero value when the inherited information is desired.
#
# @return an XML::LibXML::Document object reference.
sub buildXMLDoc {
    my ($self,
        $inclInh) = @_;
    my $rv;
    my $rootElem;
    # if ($inclInh) { _debugWrite("buildXMLDoc w/ inherited"); }
    # else { _debugWrite("buildXMLDoc W/O inherited"); }

    # create a new XML doc from scratch
    eval { $rv = XML::LibXML::Document->new("1.0", "UTF-8"); };
    FAIL("Error creating XML document: " . $@->message()) if (ref($@));
    FAIL("Error creating XML document: " . $@) if ($@);
    eval {
        $rootElem = XML::LibXML::Element->new($self->rootName());
        $rv->setDocumentElement($rootElem);
    };
    FAIL("Error creating XML Element: " . $@->message()) if (ref($@));
    FAIL("Error creating XML Element: " . $@) if ($@);

    foreach my $entityID (sort keys(%{ $self->hash() })) {
        my $entity = $self->hash($entityID);
        # skip anonymous implicitly defined entities
        next if ($entity->id() eq "DEFAULT");
        # skip named implicitly defined entities unless desired
        next unless ($inclInh || $entity->isDefined());
        my $xmlElem = $entity->toXML($self->nodeName(), $inclInh);
        $rootElem->addChild($xmlElem);
    }
    return $rv;
}


# Process a pre-filtered set of XML elements and store them.
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# $param[in] $xmlArr an array of XML::LibXML::Element objects
#   describing instances of the Entity represented by
#   $self->entityClass()
sub parseXMLElements {
    my ($self,
        $web,
        $topic,
        $xmlArr) = @_;
    foreach my $xmlElem (@{ $xmlArr }) {
        FAIL($self->entityClass() . " has no ID: " . $xmlElem->toString(0) . "\n")
            unless ($xmlElem->getAttribute("id"));
        my $elemID = $xmlElem->getAttribute("id");
        my $elemWeb = $xmlElem->getAttribute("web");
        # Do NOT parse elements from the topic currently being
        # loaded/processed.  This helps prevent storing entity
        # definitions that no longer exist, as well as prevent
        # rendering incorrect diagrams.
        if (($web eq $elemWeb) &&
            ($topic eq $xmlElem->getAttribute("topic"))) {
            push @{ $self->{'topicxml'} }, "$elemWeb.$elemID";
            next;
        }
        my $entity = $self->getEntity($elemWeb, $elemID);
        $entity->fromXML($xmlElem);
    }
}


# Execute an XPath search of data in this SimpleStore.
#
# @warning findnodes constructs the XML document including the
# inherited data.  It is assumed all data has been loaded into
# internal storage.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $query an XPath 1.0 expression.
#
# @return a list of matching XML::LibXML::Element object references.
sub findnodes {
    my ($self,
        $query) = @_;
    my @rv = ();
    $self->{'searchdoc'} = $self->buildXMLDoc(1)
        unless (defined($self->searchdoc()));
    # _debugWrite("findnodes $self " . ref($self));
    # _debugWrite("  " . ref($self->docMgr()));
    # _debugWrite("  " . ref($self->docMgr()->graphNum()));
    _debugFile("SimpleStore", $self->entityType(), sprintf("findnodes_%03d", $self->docMgr()->graphNum()), $self->searchdoc()->toString(2));
    eval {
        @rv = $self->searchdoc()->findnodes($query);
    };
    # these are likely user errors rather than internal errors, so use
    # die, not FAIL
    die("Error in search: " . $@->message . "\n") if (ref($@));
    die("Error in search: " . $@ . "\n") if ($@);
    return @rv;
}


################################
# ACCESSORS
################################

sub rootName        { return $_[0]->{'rootName'}; }
sub nodeName        { return $_[0]->{'nodeName'}; }
sub entityClass     { return $_[0]->{'entityClass'}; }
sub entityType      { return $_[0]->{'entityType'}; }
sub docMgr          { return $_[0]->{'docMgr'}; }
sub searchdoc       { return $_[0]->{'searchdoc'}; }
sub getHashKeys     { return keys %{ $_[0]->{'hash'} }; }
# 1st arg is a SimpleStore object reference
# 2nd (optional) arg is the macro spec of the desired stored data
# returns the data store hash if the 2nd arg is unspecified
# otherwise returns the requested hash member.
sub hash {
    if (defined($_[1])) { return $_[0]->{'hash'}->{ $_[1] }; }
    return $_[0]->{'hash'};
}

################################
# DATA MANAGEMENT
################################


# Get the store path, work area, and untaint regex
sub getStoreInfo {
    my ($self) = @_;
    my $workArea = Foswiki::Func::getWorkArea("DataFlowDiaPlugin");
    my $path = $workArea . "/" . $self->entityType() . ".xml";
    my $untaintExpr = qr/^($workArea\/$entityTypeRegex\.xml)$/;
    return ($path, $workArea, $untaintExpr);
}


# Load the XML file for this web and entity type.
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
sub loadFile {
    my ($self,
        $web,
        $topic) = @_;
    my ($path, $workArea, $untaintExpr) = $self->getStoreInfo();
    my $doc = undef;

    # perl doesn't check read-only open but we will.
    my $origPath = $path;
    ($path) = $path =~ m/$untaintExpr/;
    FAIL("SimpleStore::loadFile: Invalid path: $origPath")
        unless ($path);
    _debugWrite("SimpleStore::loadfile $path");
    if (-r $path) {
        open(my $fh, '<', $path)
            or FAIL("Can't open SimpleStore file \"$path\" for input: $!");
        # drop all PerlIO layers possibly created by a use open pragma
        binmode $fh;
        # make sure we don't try to read in the middle of a write
        flock($fh, LOCK_SH)
            or FAIL("Cannot lock SimpleStore file \"$path\": $!");
        $doc = XML::LibXML->load_xml(
            IO => $fh,
            no_blanks => 1);
        close($fh);
    } else {
        eval { $doc = XML::LibXML::Document->new("1.0", "UTF-8"); };
	FAIL("Error creating XML document: " . $@->message()) if (ref($@));
	FAIL("Error creating XML document: " . $@) if ($@);
    }
    if (!$doc->hasChildNodes())
    {
	eval {
	    $doc->setDocumentElement(
		XML::LibXML::Element->new($self->rootName()));
	};
	FAIL("Error creating XML Element: " . $@->message()) if (ref($@));
	FAIL("Error creating XML Element: " . $@) if ($@);
    }
    unless (-r $path) {
        # Create a file if it doesn't already exist.  Do this here
        # instead of in the earlier -r test because we need the root
        # document element added first.
        open(my $fh, ">>", $path)
            or FAIL("Can't create SimpleStore file \"$path\": $!");
        # serialize access for writing
        flock($fh, LOCK_EX)
            or FAIL("Cannot lock SimpleStore file \"$path\": $!");
        binmode $fh;
        # make sure the file hasn't been created in another session,
        # now that we have the lock.
        seek $fh, 0, SEEK_END;
        if (tell $fh == 0) {
            $doc->toFH($fh, 2);
        }
        close($fh);
    }
    my @elements = $doc->findnodes(
        "/" . $self->rootName() . "/" . $self->nodeName());
    _debugWrite("  processing " . scalar(@elements) . " XML elements");
    $self->parseXMLElements($web, $topic, \@elements);
    undef $doc;
}


# Save the contents of this
# Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore into an XML file
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
sub saveFile {
    my ($self) = @_;
    my ($path, $workArea, $untaintExpr) = $self->getStoreInfo();
    my $newDoc;
    my @removed = $self->checkForRemoved();

    # do nothing if no updates have been made
    if ((scalar(keys %{ $self->{'updated'} }) == 0) &&
        (scalar(@removed) == 0)) {
        return;
    }

    my $origPath = $path;
    ($path) = $path =~ m/$untaintExpr/;
    FAIL("SimpleStore::saveFile: Invalid path: $origPath")
        unless ($path);

    open(my $out, '+<', $path)
        or FAIL("Can't open SimpleStore file \"$path\": $!");
    # serialize access for writing
    flock($out, LOCK_EX) or FAIL("Cannot lock SimpleStore file \"$path\": $!");
    # drop all PerlIO layers possibly created by a use open pragma
    binmode $out;
    # reload the document from disk in case another session has made changes
    my $doc = XML::LibXML->load_xml(
        IO => $out,
        no_blanks => 1);

    # replace updated elements
    # document is sorted by hash keys, so advancing in lock-step should be safe
    my @changedKeys = sort keys %{ $self->{'updated'} };

    my $chgIdx = 0;
    my $chgEntity;
    my $docRoot = $doc->documentElement();
    my @elements = $docRoot->childNodes();
    my $diskIdx = 0;
    my $diskElem;
    while ($chgIdx <= $#changedKeys) {
        $chgEntity = $self->{'updated'}->{ $changedKeys[$chgIdx] };
        $diskElem = (scalar(@elements) ? $elements[$diskIdx] : undef);
        if ($diskIdx > $#elements) {
            # empty document or new element for the end, just add it.
            $docRoot->addChild($chgEntity->toXML($self->nodeName()));
            ++$chgIdx;
            next;
        }
        my $webcmp = $chgEntity->web() cmp $diskElem->getAttribute("web");
        my $idcmp =  $chgEntity->id() cmp $diskElem->getAttribute("id");
        if (($webcmp == 0) && ($idcmp == 0)) {
            # same, replace
            $diskElem->replaceNode($chgEntity->toXML($self->nodeName()));
            ++$chgIdx;
            ++$diskIdx;
        } elsif (($webcmp < 0) || (($webcmp == 0) && ($idcmp < 0))) {
            # new element
            $docRoot->insertBefore(
                $chgEntity->toXML($self->nodeName()),
                $diskElem);
            ++$chgIdx;
        } elsif (($webcmp > 0) || (($webcmp == 0) && ($idcmp > 0))) {
            # just advance the on-disk document "iterator" to try and
            # match it up with the in-memory document.
            ++$diskIdx;
        }
    }
    # remove any discarded definitions
    foreach my $webid (@removed) {
        my ($remWeb, $remID) = split(/\./, $webid);
        my @removedElems = $doc->findnodes(
            "/" . $self->rootName() .
            "/" . $self->nodeName() .
            "[\@web='$remWeb' and \@id='$remID']");
        foreach my $remElem (@removedElems) {
            _debugWrite("removing " . $remElem->toString(0));
            $remElem->parentNode->removeChild($remElem);
        }
    }

    # clear out the original contents before updating
    seek $out, 0, SEEK_SET;
    truncate $out, 0;
    $doc->toFH($out, 2);

    close($out);
}


# Handle the DFDCONNECT macro, which generates process-to-process
# graphs and text.
#
# @param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web The name of the web in the current CGI query.
# @param[in] $topic The name of the topic in the current CGI query.
# @param[in] $macroAttrs The parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $graphType Either the Entity Type stored in this
#   SimpleStore, or "GROUP" to create a connection diagram restricted
#   to entities that are members of the specified group.
#
# @return The formatted search result text (Graphviz, wiki mark-up, etc.).
sub connect {
    my ($self,
        $web,
        $topic,
        $macroAttrs,
        $graphType) = @_;
    my $rv = "";
    return macroError(
        "Missing required id parameter in " . $self->entityType() . " macro")
        unless defined($macroAttrs->{'id'});
    my $macroSpec = $macroAttrs->{'id'};
    my $graphCollection =
        Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection->new();

    if ($graphType eq $self->entityType()) {
        # get or create the desired entity
        my ($entitySpec, $entity) = $self->docMgr()->getEntityFromMacroSpec(
            $self->entityType(),
            $web,
            $macroSpec);
        my $specHashRef = undef;
        my %specHash;
        # If we're doing a data type connection graph, restrict the
        # graph to just that one data type.
        if ($graphType eq $ENTITYTYPE_DATA) {
            # Create a new EntitySpec instead of using $entitySpec,
            # which will contain the default transport.  We don't want
            # to use the default transport in this instance.
            my $macroES = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                $macroSpec, $entitySpec->web());
            %specHash = ( $macroES->spec() => $macroES );
            $specHashRef = \%specHash;
        }
        $entity->connect($macroAttrs, $graphCollection, $specHashRef);
    } elsif ($graphType eq "GROUP") {
        $self->connectGroup(
            $web, $topic, $macroAttrs, $graphCollection);
    } elsif ($graphType eq "TRANSLATION") {
        $self->connectTranslation(
            $web, $topic, $macroAttrs, $graphCollection);
    } else {
        FAIL("Unexpected graph type \"$graphType\"");
    }
    my $graphText = $graphCollection->render($macroAttrs, 0, $self->docMgr());
    $rv .= $graphText;
    undef $graphCollection;
    # _debugWrite($graphText);

    return $rv;
}


# Handle the DFDCONNECT macro when the entities are restricted to
# members of a specific group.
#
# @param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web The name of the web in the current CGI query.
# @param[in] $topic The name of the topic in the current CGI query.
# @param[in] $macroAttrs The parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in,out] $graphCollection A GraphCollection object reference to
#   store the results of the connection-building.
sub connectGroup {
    my ($self,
        $web,
        $topic,
        $macroAttrs,
        $graphCollection) = @_;
    my $docMgr = $self->docMgr();
    my $group = $docMgr->getEntityFromMacroSpec(
        $ENTITYTYPE_GROUP, $web, $macroAttrs->{'id'});
    my $dataGroupHash = $group->data();
    my %specHash = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->specHash(
        $dataGroupHash);
    foreach my $key (keys %{ $dataGroupHash }) {
        $dataGroupHash->{$key}->connect(
            $macroAttrs, $graphCollection, \%specHash);
    }
}


# Handle the DFDCONNECT macro when the entities are restricted to
# a data type and any translated data types.
#
# @param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web The name of the web in the current CGI query.
# @param[in] $topic The name of the topic in the current CGI query.
# @param[in] $macroAttrs The parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in,out] $graphCollection A GraphCollection object reference to
#   store the results of the connection-building.
sub connectTranslation {
    my ($self,
        $web,
        $topic,
        $macroAttrs,
        $graphCollection) = @_;
    # get or create the desired entity
    my ($entitySpec, $entity) = $self->docMgr()->getEntityFromMacroSpec(
        $self->entityType(),
        $web,
        $macroAttrs->{'id'});
    # Create a new EntitySpec instead of using $entitySpec,
    # which will contain the default transport.  We don't want
    # to use the default transport in this instance.
    my $macroES = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $macroAttrs->{'id'}, $entitySpec->web());
    my %specHash = ( $macroES->spec() => $macroES );
    $entity->connect($macroAttrs, $graphCollection, \%specHash);
}


# Return an existing or new entity with the given web and ID.
#
# @note The return value is not simply an Entity object reference, but
# an object reference to one of the child classes,
# e.g. Foswiki::Plugins::DataFlowDiaPlugin::Process.  This class is
# the value of $self->entityClass(), which is set in the new()
# method.
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# $param[in] $web the name of the web where the desired entity is defined.
# $param[in] $id the ID of the desired entity.
#
# @return an object reference to a child of the Entity package/class.
sub getEntity {
    my ($self,
        $web,
        $id) = @_;
    my $hashKey = $web . "." . $id;
    if (!defined($self->hash($hashKey))) {
        $self->storeEntity(
            $self->entityClass()->new($web, $id, $self->docMgr()));
    }
    return $self->hash($hashKey);
}


# Add or replace an Entity in this SimpleStore.
#
# $param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# $param[in] $entity An Entity object reference to be stored.
sub storeEntity {
    my ($self,
        $entity) = @_;
    my $hashKey = $entity->web() . "." . $entity->id();
    $self->{'hash'}->{$hashKey} = $entity;
}


# Designate an Entity in this SimpleStore as being a member of a group.
#
# $param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# $param[in] $entity An Entity object reference to be stored.
sub addToGroup {
    my ($self,
        $entity) = @_;
    my $hashKey = $entity->getMacroSpec();
    $self->{'grouphash'}->{$_}->{$hashKey} = $entity
        foreach (keys %{ $self->groups() });
}


# Clear any internal storage used strictly for XML XPath queries.
#
# $param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
sub clearSearchMeta {
    my ($self) = @_;
    $self->hash($_)->clearSearchMeta()
        foreach (keys %{ $self->hash() });
}


# Indicate that an entity in this store has been modified by a macro.
sub markChanged {
    my ($self,
        $entity) = @_;
    my $hashKey = $entity->web() . "." . $entity->id();
    $self->{'updated'}->{$hashKey} = $entity;
}


# Determine if any entity definitions have been removed.
sub checkForRemoved {
    my ($self) = @_;
    my @removed = difference($self->{'topicmacro'}, $self->{'topicxml'});
    return @removed;
}


################################
# GRAPHVIZ PROCESSING
################################


# Render the definition macros (DFDPROC, DFDDATA, DFDTRANSPORT,
# DFDLOCALE) as an HTML anchor and possibly graph.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return An HTML anchor and possibly a Graphviz graph definition for
#   the defined Entity.
sub renderDefn {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;
    return macroError(
        "Missing required id parameter in " . $self->entityType() . " macro")
        unless defined($macroAttrs->{'id'});
    my $macroSpec = $macroAttrs->{'id'};
    # get or create the desired entity
    my ($entitySpec, $entity) = $self->docMgr()->getEntityFromMacroSpec(
        $self->entityType(),
        $web,
        $macroSpec);
    my $rv = "";
    my $graphCollection =
        Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection->new(1);
    $entity->defnGraph($macroAttrs, $graphCollection);
    $graphCollection->setAnchor($entity->getAnchorName());
    my $graphText = $graphCollection->render($macroAttrs, 1, $self->docMgr());
    $rv .= $graphText;

    return $rv;
}


1;
