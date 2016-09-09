# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/Process.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::Process

Entity class for DataFlowDiaPlugin processes.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::Process;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Entity qw(macroToList getRef getRefFromXML derefHash);
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::DataTransport;
use Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation;
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:dirs :etypes);

use vars qw(@ISA);
@ISA = ('Foswiki::Plugins::DataFlowDiaPlugin::Entity');

################################
# CONSTRUCTORS
################################

# Create a new Process object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $web the wiki web name containing the process definitions
# @param[in] $id the web-unique identifier for this Process
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
#  @return a reference to a Process object
sub new {
    my ($class,
        $web,
        $id,
        $docManager) = @_;
    my $self = $class->SUPER::new($web, $id, $docManager);
    # These three fields are hashes of DataTransport object references.
    $self->{'inputs'} = {};
    $self->{'outputs'} = {};
    $self->{'inouts'} = {};
    # Hash to Locale object references
    $self->fromMacroXref(
        $ENTITYTYPE_LOCALE,
        'locales', $web, { 'locales' => "DEFAULT" }, 0, 'processes');
    # These fields are only used for XML XPath queries and are filled
    # by storeMatch
    $self->{'matchedinputs'} = {};
    $self->{'matchedoutputs'} = {};
    $self->{'matchedinouts'} = {};
    $self->{'matchedlocales'} = {};
    # Hash to DataTranslation object references
    $self->{'translations'} = {};
    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################

# Pre-process Process definition macros, storing the subroutine
# parameters and hash values into $self.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web containing the definition for
#   this Process.
# @param[in] $topic the name of the topic containing the definition
#   for this Process.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
#
# @pre $macroAttrs->{'id'} is valid
# @pre $self->{'docMgr'} is set to a DocManager reference
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromMacro {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;
    $self->SUPER::fromMacro($web, $topic, $macroAttrs);

    # These three fields are hashes of DataTransport object references.
    $self->{'inputs'} = {};
    $self->{'outputs'} = {};
    $self->{'inouts'} = {};
    # Hash to Locale object references
    $self->{'locales'} = {};
    # These fields are only used for XML XPath queries and are filled
    # in GraphCollection.pm
    $self->{'matchedinputs'} = {};
    $self->{'matchedoutputs'} = {};
    $self->{'matchedinouts'} = {};
    $self->{'matchedlocales'} = {};
    # Hash to DataTranslation object references
    $self->{'translations'} = {};

    $self->fromMacroDataTypeXref(
        'inputs', 'inxport',    'consumers', $web, $macroAttrs);
    $self->fromMacroDataTypeXref(
        'outputs','outxport',   'producers', $web, $macroAttrs);
    $self->fromMacroDataTypeXref(
        'inouts', 'inoutxport', 'loopers',   $web, $macroAttrs);
    $self->fromMacroXref(
        $ENTITYTYPE_LOCALE,
        'locales', $web, $macroAttrs, 0, 'processes');
    if (!%{ $self->{'locales'} }) {
        # no locale specified, use default
        $self->fromMacroXref(
            $ENTITYTYPE_LOCALE,
            'locales', $web, { 'locales' => "DEFAULT" }, 0, 'processes');
    }
    # translations have a unique syntax
    $self->fromMacroTranslation($web, $macroAttrs);
}


# Process DataType cross-references and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $paramName a string naming the internal hash key where
#   these cross-references are stored.
# @param[in] $xportAttrName the Foswiki::Attrs hash key containing
#   the expected transport cross-reference for these data types.
# @param[in] $dataParamName a string naming the internal hash key of
#   DataType where the reverse cross-references are stored.
# @param[in] $web the name of the web where the desired entity is defined.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
sub fromMacroDataTypeXref {
    my ($self,
        $paramName,
        $xportAttrName,
        $dataParamName,
        $web,
        $macroAttrs) = @_;
    # clear out any existing data so old information is not retained,
    # but make sure that the field is set to at least an empty hash ref.
    $self->{$paramName} = {};

    # TODO the ugly part here is that the locale process connections
    # AREN'T being zilched out, so it's entirely possible that some
    # wrong information will be propagated on the first save after
    # updating connections.

    if (defined($macroAttrs->{$paramName})) {
        my @xrefList = macroToList($macroAttrs->{$paramName});
        foreach my $dataMacroSpec (@xrefList) {
            my $dt = Foswiki::Plugins::DataFlowDiaPlugin::DataTransport->new(
                $web,
                $dataMacroSpec,
                $macroAttrs->{$xportAttrName},
                paramName2Dir($paramName),
                $self->docMgr());
            my $hashKey = $dt->macroSpec();
            $self->{$paramName}->{$hashKey} = $dt;
            $dt->addProcess($self, $dataParamName);
        }
    }
}


# Process DataTranslation definitions and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web where the desired entity is defined.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
sub fromMacroTranslation {
    my ($self,
        $web,
        $macroAttrs) = @_;

    # clear out any existing data so old information is not retained,
    # but make sure that the field is set to at least an empty hash ref.
    $self->{'translations'} = {};

    if (defined($macroAttrs->{'translation'})) {
        my @translationList = macroToList($macroAttrs->{'translation'});
        foreach my $xlateMacroSpec (@translationList) {
            my $dt = Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation->new(
                $web,
                $xlateMacroSpec,
                $self->docMgr());
            my $hashKey = $dt->macroSpec();
            $self->{'translations'}->{$hashKey} = $dt;
            # reverse references
            $dt->fromDataEntity()->addTranslator($self, "from");
            $dt->toDataEntity()->addTranslator($self, "to");
        }
    }
}


################################
# XML PROCESSING
################################

# Update the hash values in this Process using the attributes of an
# XML::LibXML::Element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   Process definition.
#
# @pre "id", "name", "web" and "topic" attributes are set in $xmlElem
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromXML {
    my ($self,
        $xmlElem) = @_;

    $self->SUPER::fromXML($xmlElem);

    $self->fromXMLDataTypeXref('inputs',  'consumers', $xmlElem, "input");
    $self->fromXMLDataTypeXref('outputs', 'producers', $xmlElem, "output");
    $self->fromXMLDataTypeXref('inouts',  'loopers',   $xmlElem, "inout");
    $self->fromXMLXref(
        $ENTITYTYPE_LOCALE,
        'locales', $xmlElem, "locale", 'processes');
    if (!%{ $self->{'locales'} }) {
        # no locale specified, use default
        $self->fromMacroXref(
            $ENTITYTYPE_LOCALE,
            'locales', $self->{'web'}, { 'locales' => "DEFAULT" }, 0,
            'processes');
    }
    # translations have a unique syntax
    $self->fromXMLTranslation($xmlElem);
}


# Process DataType cross-references and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $paramName a string naming the internal hash key where
#   these cross-references are stored.
# @param[in] $dataParamName a string naming the internal hash key of
#   DataType where the reverse cross-references are stored.
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   Process definition.
# @param[in] $nodename the name of the XML child node containing
#   cross-references.
sub fromXMLDataTypeXref {
    my ($self,
        $paramName,
        $dataParamName,
        $xmlElem,
        $nodename) = @_;

    my @datanodelist = $xmlElem->findnodes($nodename);
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);

    foreach my $xmlDataNode (@datanodelist) {
        my $dt = Foswiki::Plugins::DataFlowDiaPlugin::DataTransport->newXML(
            $xmlDataNode,
            paramName2Dir($paramName),
            $self->docMgr());
        my $hashKey = $dt->macroSpec();
        $self->{$paramName}->{$hashKey} = $dt;
        $dt->addProcess($self, $dataParamName);
    }
}


# Process DataTranslation definitions and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   Process definition.
sub fromXMLTranslation {
    my ($self,
        $xmlElem) = @_;

    my @nodelist = $xmlElem->findnodes("translation");
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);

    foreach my $xmlNode (@nodelist) {
        my $dt = Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation->newXML(
            $xmlNode,
            $self->docMgr());
        my $hashKey = $dt->macroSpec();
        $self->{'translations'}->{$hashKey} = $dt;
        # reverse references
        $dt->fromDataEntity()->addTranslator($self, "from");
        $dt->toDataEntity()->addTranslator($self, "to");
    }
}


# Create and return a new XML::LibXML::Element with attributes set
# according to the hash values in this Process.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing this Process.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
#
# @pre "id", "name", "web" and "topic" hash values are set in $self
sub toXML {
    my ($self,
        $elementName,
        $inclInh) = @_;

    my $rv = $self->SUPER::toXML($elementName, $inclInh);

    $self->toXMLDataTypeXref('inputs',  'input',  $rv, $inclInh);
    $self->toXMLDataTypeXref('outputs', 'output', $rv, $inclInh);
    $self->toXMLDataTypeXref('inouts',  'inout',  $rv, $inclInh);
    $self->toXMLXref('locales', 'locale', $rv, $inclInh);
    if ($inclInh) {
        $self->toXMLDataTypeXref(
            'matchedinputs',  'matchedinput',  $rv, $inclInh);
        $self->toXMLDataTypeXref(
            'matchedoutputs', 'matchedoutput', $rv, $inclInh);
        $self->toXMLDataTypeXref(
            'matchedinouts',  'matchedinout',  $rv, $inclInh);
        $self->toXMLXref(
            'matchedlocales', 'matchedlocale', $rv, $inclInh);
    }
    $self->toXMLTranslation($rv, $inclInh);

    return $rv;
}


# Add child nodes to XML::LibXML::Element for I/O cross-references
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $paramName the name of the hash element in $self
#   containing a hash reference to Entity object references,
#   i.e. $self->{$paramName}->{SOME_KEY}->ref(Entity).
# @param[in] $xmlChildName the name of the child node in the XML store
#   representing the data types stored in $paramName.
# @param[in] $xmlElem the XML::LibXML::Element of which the new nodes
#   will be children.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
sub toXMLDataTypeXref {
    my ($self,
        $paramName,
        $xmlChildName,
        $xmlElem,
        $inclInh) = @_;

    foreach my $key (sort keys %{ $self->{$paramName} }) {
        my $dt = $self->{$paramName}->{$key};
        my $dataChild = $dt->toXML($xmlChildName, $inclInh);
        $xmlElem->addChild($dataChild);
    }
}


# Add child nodes to XML::LibXML::Element for DataType translations
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem the XML::LibXML::Element of which the new nodes
#   will be children.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
sub toXMLTranslation {
    my ($self,
        $xmlElem,
        $inclInh) = @_;

    foreach my $key (sort keys %{ $self->{'translations'} }) {
        my $dt = $self->{'translations'}->{$key};
        $xmlElem->addChild($dt->toXML($inclInh));
    }
}


# Each Entity structure has an XML representation and within that
# representation are cross-references to other data types.  In order
# to determine how to handle those cross-references, child classes
# must implement this method to map $xmlElem to an Entity Type (see
# DocManager).
#
# @param[in] $xmlElem an XML::LibXML::Element object reference
#   containing a cross-reference.
#
# @return either an Entity Type string or undef if the XML element
#   does not contain a known cross-reference node.
sub getEntityTypeFromXML {
    my ($class, $xmlElem) = @_;
    # SMELL surely there's a better way to do this...
    if (($xmlElem->nodeName eq "locale") ||
        ($xmlElem->nodeName eq "matchedlocale")) {
        return $ENTITYTYPE_LOCALE;
    }
    if ($xmlElem->nodeName eq "xport") {
        return $ENTITYTYPE_XPORT;
    }
    if (($xmlElem->nodeName eq "input") ||
        ($xmlElem->nodeName eq "output") ||
        ($xmlElem->nodeName eq "inout") ||
        ($xmlElem->nodeName eq "matchedinput") ||
        ($xmlElem->nodeName eq "matchedoutput") ||
        ($xmlElem->nodeName eq "matchedinout") ||
        ($xmlElem->nodeName eq "from") ||
        ($xmlElem->nodeName eq "to")) {
        return $ENTITYTYPE_DATA;
    }
    return undef;
}


################################
# ACCESSORS
################################

# The following subs are hash accessors.
# 1st arg is a Process object reference.
# 2nd (optional) arg is the key of a specific hash element to retrieve.

sub inputs
{
    if (defined($_[1])) { return $_[0]->{'inputs'}->{ $_[1] }; }
    return $_[0]->{'inputs'};
}
sub outputs
{
    if (defined($_[1])) { return $_[0]->{'outputs'}->{ $_[1] }; }
    return $_[0]->{'outputs'};
}
sub inouts
{
    if (defined($_[1])) { return $_[0]->{'inouts'}->{ $_[1] }; }
    return $_[0]->{'inouts'};
}
sub locales
{
    if (defined($_[1])) { return $_[0]->{'locales'}->{ $_[1] }; }
    return $_[0]->{'locales'};
}
sub matchedinputs
{
    if (defined($_[1])) { return $_[0]->{'matchedinputs'}->{ $_[1] }; }
    return $_[0]->{'matchedinputs'};
}
sub matchedoutputs
{
    if (defined($_[1])) { return $_[0]->{'matchedoutputs'}->{ $_[1] }; }
    return $_[0]->{'matchedoutputs'};
}
sub matchedinouts
{
    if (defined($_[1])) { return $_[0]->{'matchedinouts'}->{ $_[1] }; }
    return $_[0]->{'matchedinouts'};
}
sub matchedlocales
{
    if (defined($_[1])) { return $_[0]->{'matchedlocales'}->{ $_[1] }; }
    return $_[0]->{'matchedlocales'};
}
sub translations {
    if (defined($_[1])) { return $_[0]->{'translations'}->{ $_[1] }; }
    return $_[0]->{'translations'};
}


################################
# DATA MANAGEMENT
################################


# get an arbitrary valid (macrospec, locale) pair for this Process
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
sub getAnyLocale {
    my ($self) = @_;
    # definition graphs do not render locales so just use the first locale
    # sorted for consistent results each time
    my ($localeMacroSpec) = sort keys %{ $self->{'locales'} };
    return ($localeMacroSpec, $self->{'locales'}->{$localeMacroSpec});
}


# Construct Entity connections (data flow) and store them in $graphCollection.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
# @param[in] $specHash an optional reference to a hash of EntitySpec
#   object references which, if specified, will be used to filter
#   DataTypes that do not match.
# @param[in] $locales an optional reference to a hash of Locale object
#   references which will be used as an alternative to all known
#   locales for this Process.
sub connect {
    my ($self,
        $macroAttrs,
        $graphCollection,
        $specHash,
        $locales) = @_;
    # SMELL should this be used, but include the locale as well?  Is
    # it necessary at all?  I think it was to prevent infinite loops.
    # Without the locale, you'll get diagrams with only one instance
    # of any given app, which is not desirable.
#    if ($graphCollection->hasProcess($self)) {
#        return;
#    }
    if ($macroAttrs->{'hidedeprecated'} && $self->isDeprecated()) {
        return;
    }
    my %matchingLocales =
        Foswiki::Plugins::DataFlowDiaPlugin::Locale::filterLocales(
            $locales || $self->locales(),
            $macroAttrs);

    $graphCollection->addProcess($_, $matchingLocales{$_}, $self)
        foreach (keys %matchingLocales);
    $graphCollection->setProcess($self);

    # check our termination condition
    if ($macroAttrs->{'level'} <= 0) {
        return;
    }

    my %macroAttrsCopy = %{ $macroAttrs };
    my %specHashCopy;
    # Don't pass empty specHash unless given an empty specHash.
    my $specHashCopyRef = (defined($specHash) ? \%specHashCopy : undef);
    if (defined($specHash)) {
        %specHashCopy = %{ $specHash };
    }
    $macroAttrsCopy{'level'}--;
    if ($macroAttrs->{'type'} =~ /^translation$/i) {
        # Because we're looking for translations, we need to get the
        # translations in reverse, i.e. backwards connections need to
        # have translations where the specHash is the TARGET, and the
        # source must then be added to the specHash for the DIR_BACK
        # connectData call
        foreach my $iodtKey (keys %{ $self->outputs() }) {
            my $dt = $self->outputs($iodtKey);
            my $dataES = $dt->dataEntitySpec();
            next if (!$dataES->matchHash($specHash, 1));
            # DIR_BACK means the data type is an input, therefore the
            # translation data type to look for will be the "from"
            # data type.
            foreach my $xlateKey (keys %{ $self->translations() }) {
                my $xlate = $self->translations($xlateKey);
                my $xles = $xlate->toDataEntitySpec();
                my $xlms = $xlate->fromDataMacroSpec();
                if ($xles->matchID($dataES, 1)) {
                    $specHashCopy{ $xlms } = $xlate->fromDataEntitySpec();
                }
            }
        }
    }
    if ($macroAttrs->{'dir'} & $DIR_BACK) {
        $macroAttrsCopy{'dir'} = $DIR_BACK;
        $self->connectData(
            $DIR_BACK,
            \%macroAttrsCopy,
            \%matchingLocales,
            $graphCollection,
            $specHashCopyRef);
    }
    # clean out any extra stuff we might have added from translation matches
    if (defined($specHash)) {
        %specHashCopy = %{ $specHash };
    }
    if ($macroAttrs->{'type'} =~ /^translation$/i) {
        foreach my $iodtKey (keys %{ $self->inputs() }) {
            my $dt = $self->inputs($iodtKey);
            my $dataES = $dt->dataEntitySpec();
            next if (!$dataES->matchHash($specHash, 1));
            foreach my $xlateKey (keys %{ $self->translations() }) {
                my $xlate = $self->translations($xlateKey);
                my $xles = $xlate->fromDataEntitySpec();
                my $xlms = $xlate->toDataMacroSpec();
                if ($xles->matchID($dataES, 1)) {
                    $specHashCopy{ $xlms } = $xlate->toDataEntitySpec();
                }
            }
        }
    }
    if ($macroAttrs->{'dir'} & $DIR_FWD) {
        $macroAttrsCopy{'dir'} = $DIR_FWD;
        $self->connectData(
            $DIR_FWD,
            \%macroAttrsCopy,
            \%matchingLocales,
            $graphCollection,
            $specHashCopyRef);
    }
}


# Construct Entity connections for DataType cross-references and store
# them in $graphCollection.  The connections are formed by locale,
# transport and data type combinations.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $connectDir a number indicating the direction of the edge
#   relative to this process (see DocManager).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in] $locales a hash of locale macro specs to Locale Entity
#   object references to match connecting processes against.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
# @param[in] $specHash an optional reference to a hash of EntitySpec
#   object references which, if specified, will be used to filter
#   DataTypes that do not match.
sub connectData {
    my ($self,
        $connectDir,
        $macroAttrs,
        $locales,
        $graphCollection,
        $specHash) = @_;
    my $ioParamName = dir2ParamName($connectDir);

    # Iterate through all inputs, outputs or inouts depending on
    # $connectDir, i.e. iterate through all data types associated with
    # this processes.
    # if ($self->id() eq "someprocessid") {
    #     _debugFuncStart("connectData(someprocessid, $connectDir, ...)");
    #     _debugWrite("keys for $ioParamName:");
    #     _debugWrite("    $_") foreach (keys %{ $self->{$ioParamName} });
    #     _debugWrite("keys for locales:");
    #     _debugWrite("    $_") foreach (keys %{ $locales });
    # }
    foreach my $iodtKey (keys %{ $self->{$ioParamName} }) {
        # $dt is the DataTransport reference IN THIS PROCESS
        # $dataEntity is the DataType Entity of the DataTransport
        # $dataES is the EntitySpec for the DataType in $dt
        my $dt = $self->{$ioParamName}->{$iodtKey};
        my $dataEntity = $dt->dataEntity();
        my $dataES = $dt->dataEntitySpec();

        # Skip DataType entities that are not part of the requested
        # group, if there was one.
        next if (!$dataES->matchHash($specHash, 1));

        # Get a hash of *potentially* connected Process Entity
        # objects.  These are just the objects that the DataType knows
        # about, unfiltered by Locale/Transport.
        my $procXports = $dataEntity->getConProc(
            $connectDir, $dt->entitySpec());

        # if ($self->id() eq "someprocessid") {
        #     _debugWrite("keys for procXports:");
        #     _debugWrite("    $_") foreach (keys %{ $procXports });
        # }

        # we have our data entity in $dataEntity
        #   our processes using $dataEntity in $procXports
        #   our transports in both $dt and $procXports
        #   the locales we might be sending to or receiving from are in $locales
        # data types can be rendered between subgraphs, if nolocales=false,
        # or not at all if datanodes=false

        # go through each of the matching locales for THIS process
        foreach my $lockey (keys %{ $locales }) {
            my $myLocEntity = $locales->{$lockey};
            my %locCons = ();
            $myLocEntity->hashConByXport(
                $dt->xportMacroSpec(),
                \%locCons,
                $connectDir,
                $macroAttrs);

            # if ($self->id() eq "someprocessid") {
            #     _debugWrite("keys for locCons ($lockey):");
            #     _debugWrite("    $_") foreach (keys %locCons);
            # }

            # %locCons now contains a hash of LocaleTransport
            # references to which the locale referred to by
            # $lockey connects

            # Render leaf nodes if $specHash is defined (which is a
            # matching set of DataTypes, i.e. DataType objects that
            # are expected to appear in the graph), but no Processes
            # are connected.
            # We do NOT want to do this if either Processes are
            # connected, nor do we want to do this if $specHash is
            # undefined, as this would result in the rendering of
            # DataType nodes that aren't relevant to the connection
            # diagram.
            if ($specHash && !%{ $procXports }) {
                # SMELL I'm not convinced this should be single-instance
                $graphCollection->addDataLeaf($myLocEntity, $self, $dt, 1);
            }
            foreach my $ptkey (keys %{ $procXports }) {
                my $targetLocales = $procXports->{$ptkey}->matchLocales(
                    \%locCons);
                my $cnctProc = $procXports->{$ptkey}->processEntity();
                my $cnctDT = $cnctProc->reverseDataXport(
                    $dt->entitySpec(), $connectDir);
                # if ($self->id() eq "someprocessid") {
                #     _debugWrite("keys for targetLocales:");
                #     _debugWrite("    $_") foreach (keys %{ $targetLocales });
                # }
                foreach my $tgtlockey (keys %{ $targetLocales }) {
                    # restrict the next connect() call to just this locale
                    my %tmpLocHash =
                        ( $tgtlockey => $targetLocales->{$tgtlockey} );

                    # need to check hidedeprecated here to prevent
                    # addEdge etc. being called on a non-existent process.
                    next if ($macroAttrs->{'hidedeprecated'} &&
                             $cnctProc->isDeprecated());
                    # edges to one's self are fine, but don't recurse
                    # any further for self edges.
                    if ($cnctProc != $self) {
                        $cnctProc->connect(
                            $macroAttrs, $graphCollection, $specHash,
                            \%tmpLocHash);
                    }
                    $graphCollection->addEdge(
                        $myLocEntity,
                        $self,
                        $dt,
                        $targetLocales->{$tgtlockey},
                        $cnctProc,
                        $cnctDT,
                        $connectDir);
                    # store matched entities for queries
                    $self->storeMatch($dt, $myLocEntity);
                    $cnctProc->storeMatch($cnctDT,$targetLocales->{$tgtlockey});
                }
            }
        }
    }
    # if ($self->id() eq "someprocessid") {
    #     _debugFuncEnd("connectData(someprocessid, $connectDir, ...)");
    # }
}


# Get the DocManager direction value matching a Process DataTransport
# internal hash key.
# @param[in] $paramName the internal hash key.
sub paramName2Dir {
    my ($paramName) = @_;
    if ($paramName eq "inputs") {
        return $DIR_BACK;
    } elsif ($paramName eq "outputs") {
        return $DIR_FWD;
    } elsif ($paramName eq "inouts") {
        return $DIR_BOTH;
    }
    FAIL("paramName2Dir unknown paramName value $paramName");
}


# Get the Process DataTransport internal hash key matching a
# DocManager direction value.
# @param[in] $dir the DocManager direction value
sub dir2ParamName {
    my ($dir) = @_;
    if ($dir == $DIR_BACK) {
        return "inputs";
    } elsif ($dir == $DIR_FWD) {
        return "outputs";
    } elsif ($dir == $DIR_BOTH) {
        return "inouts";
    }
    FAIL("dir2ParamName unknown dir value $dir");
}


# Get the Process DataTransport internal hash key matching THE OPPOSITE
# DocManager direction value.
# @param[in] $dir the DocManager direction value
sub dir2ReverseParamName {
    my ($dir) = @_;
    if ($dir == $DIR_BACK) {
        return "outputs";
    } elsif ($dir == $DIR_FWD) {
        return "inputs";
    } elsif ($dir == $DIR_BOTH) {
        return "inouts";
    }
    FAIL("dir2ParamName unknown dir value $dir");
}


# Get the DataTransport object reference matching the given entity spec.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# 
sub reverseDataXport {
    my ($self,
        $dtEntitySpec,
        $connectDir) = @_;
    my $paramName = dir2ReverseParamName($connectDir);
    # first, try direct match
    if (defined($self->{$paramName}->{ $dtEntitySpec->macroSpec() })) {
        return $self->{$paramName}->{ $dtEntitySpec->macroSpec() };
    }
    # linear search because matching sub-ids and DEFAULT and what-not :-P
    foreach my $key (keys %{ $self->{$paramName} }) {
        my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
            $key, $self->web());
        if ($es->match($dtEntitySpec)) {
            undef $es;
            return $self->{$paramName}->{$key};
        }
        undef $es;
    }
}


# Clear any internal storage used strictly for XML XPath queries.
sub clearSearchMeta {
    my ($self) = @_;
    $self->{'matchedinputs'} = {};
    $self->{'matchedoutputs'} = {};
    $self->{'matchedinouts'} = {};
    $self->{'matchedlocales'} = {};
}


# Store cross-reference data matching a CONNECT query
sub storeMatch {
    my ($self,
        $dataTransport,
        $locale) = @_;
    my $dtHashKey = $dataTransport->macroSpec();
    my $ioParamName = "matched" . dir2ParamName($dataTransport->dir());
    my $locHashKey = $locale->getMacroSpec();
    $self->{$ioParamName}->{$dtHashKey} = $dataTransport;
    $self->{'matchedlocales'}->{$locHashKey} = $locale;
}


################################
# GRAPHVIZ PROCESSING
################################

# Generate the nodes and edges representing the simple graph
# representing only the basic definition of this Process.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
sub defnGraph {
    my ($self,
        $macroAttrs,
        $graphCollection) = @_;
    my ($localeMacroSpec, $localeEntity) = $self->getAnyLocale();

    $graphCollection->addProcess(
        $localeMacroSpec,
        $localeEntity,
        $self);

    foreach my $dataIOParam ('inputs', 'outputs', 'inouts') {
        foreach my $dtkey (sort keys %{ $self->{$dataIOParam} }) {
            $graphCollection->addDataLeaf(
                $localeEntity,
                $self,
                $self->{$dataIOParam}->{$dtkey});
        }
    }
}


# graphviz options to use when rendering this Process as a node
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
sub getDotNodeOptions {
    my $self = shift;
    return $Foswiki::Plugins::DataFlowDiaPlugin::procNodeDepDefault
        if ($self->{'deprecated'});
    return $Foswiki::Plugins::DataFlowDiaPlugin::procNodeDefault;
}


################################
# WIKI/WEB PROCESSING
################################

# @return the beginning of the anchor name for all Process anchors.
sub getAnchorTag {
    return "DfdProc";
}

1;
