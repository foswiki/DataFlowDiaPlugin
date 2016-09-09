# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/EntitySpec.pm#3 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec

Define a class for the identification of entities.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :debug);

################################
# CONSTRUCTORS
################################

# Create a new EntitySpec object from wiki macro text.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $macroSpec the wiki macro text identifying an entity
# @param[in] $defaultWeb the wiki web name containing the entity definitions
#
# @return a reference to an EntitySpec object
sub new {
    my ($class,
        $macroSpec,
        $defaultWeb) = @_;
    my ($refid, $subid, $flags, $xprefid, $xpsub) = split(/\#/, $macroSpec);
    FAIL("empty reference") unless $refid;

    # break apart the refid into web and id
    my ($id, $web) = (reverse split(/\./, $refid));
    $web = $web || $defaultWeb;
    $subid = $subid || "DEFAULT";
    $flags = $flags || "";

    FAIL ("\"" . $id . "\" is not a valid identifier")
        unless (isValidID($id));
    FAIL ("\"" . $subid . "\" is not a valid sub-identifier")
        unless (isValidID($subid));
    FAIL ("\"" . $web . "\" is not a valid web identifier")
        unless ($web =~ m/^$Foswiki::regex{webNameRegex}$/);

    # make sure xprefid has SOMETHING so perl doesn't whine
    $xprefid = ''
        unless($xprefid);
    my ($xpid, $xpweb) = (reverse split(/\./, $xprefid));
    $xpweb = $xpweb || $defaultWeb;
    $xpid  = $xpid  || "DEFAULT";
    $xpsub = $xpsub || "DEFAULT";

    FAIL ("\"" . $xpid . "\" is not a valid identifier")
        unless (isValidID($xpid));
    FAIL ("\"" . $xpsub . "\" is not a valid sub-identifier")
        unless (isValidID($xpsub));
    FAIL ("\"" . $xpweb . "\" is not a valid web identifier")
        unless ($xpweb =~ m/^$Foswiki::regex{webNameRegex}$/);

    my $self = {
        'refid'      => $refid,
        'spec'       => $web . "." . $id . "#" . $subid,
        'subid'      => $subid,
        'id'         => $id,
        'web'        => $web,
        'flags'      => $flags,
        'xprefid'    => $xprefid,
        'xpweb'      => $xpweb,
        'xpid'       => $xpid,
        'xpsub'      => $xpsub,
        'xpspec'     => $xpweb . "." . $xpid . "#" . $xpsub
    };
    return bless ($self, $class);
}


# Create a new EntitySpec object from an XML::LibXML::Element.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $xmlElem an XML::LibXML::Element object containing at
#   a bare minimum, the "id" and "web" attributes.
#
# @return a reference to an EntitySpec object
sub newXML {
    my ($class,
        $xmlElem) = @_;

    my $id    = $xmlElem->getAttribute("id");
    my $web   = $xmlElem->getAttribute("web");
    my $subid = $xmlElem->getAttribute("subid") || "DEFAULT";
    my $flags = $xmlElem->getAttribute("flags") || "";

    # set defaults if no transport is specified
    my $xprefid = '';
    my $xpweb = $web;
    my $xpid  = "DEFAULT";
    my $xpsub = "DEFAULT";

    # try to get transport info from a transport child node
    my @xportnodelist = $xmlElem->findnodes("xport");
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);
    # there can be only one.
    if (scalar(@xportnodelist)) {
        my $xportEntitySpec = $class->newXML($xportnodelist[0]);
        $xpweb   = $xportEntitySpec->web();
        $xpid    = $xportEntitySpec->id();
        $xpsub   = $xportEntitySpec->subid();
        $xprefid = $xportEntitySpec->refid();
    }

    my $self = {
        'refid'      => $web . "." . $id,
        'spec'       => $web . "." . $id . "#" . $subid,
        'subid'      => $subid,
        'id'         => $id,
        'web'        => $web,
        'flags'      => $flags,
        'xprefid'    => $xprefid,
        'xpweb'      => $xpweb,
        'xpid'       => $xpid,
        'xpsub'      => $xpsub,
        'xpspec'     => $xpweb . "." . $xpid . "#" . $xpsub
    };
    return bless ($self, $class);
}


# Create a new EntitySpec object from an Entity.
#
# @param[in] $class The name of the class being instantiated.
# @param[in] $entity the Entity object reference.
# @param[in] $xportEntity (optional) the Transport object reference.
# @param[in] $macroSpec (optional) the wiki macro text identifying an
#   entity; used to get parts of the EntitySpec not typically
#   available in an Entity object, e.g. sub-ID.
#
# @return a reference to an EntitySpec object
sub newEntity {
    my ($class,
        $entity,
        $xportEntity,
        $macroSpec) = @_;
    my ($web, $id, $subid) = ($entity->web(), $entity->id(), $entity->subid());
    my $refid = $web . "." . $id;
    my ($xpweb, $xpid, $xpsub) = ($web, "DEFAULT", "DEFAULT");
    if (defined($xportEntity)) {
        $xpweb = $xportEntity->web();
        $xpid  = $xportEntity->id();
        $xpsub = $xportEntity->subid();
    }
    my $xprefid = $xpweb . "." . $xpid;
    my $self = {
        'refid'      => $refid,
        'spec'       => $refid . "#" . $subid,
        'subid'      => $subid,
        'id'         => $id,
        'web'        => $web,
        'flags'      => $entity->flags(),
        'xprefid'    => $xprefid,
        'xpweb'      => $xpweb,
        'xpid'       => $xpid,
        'xpsub'      => $xpsub,
        'xpspec'     => $xprefid . "#" . $xpsub
    };
    if ($macroSpec) {
        # note the name reuse, because I'm lazy copypasta
        my ($mrefid, $msubid, $mflags, $mxprefid, $mxpsub) =
            split(/\#/, $macroSpec);
        # can be ignored, as they should always match:
        #   refid
        #   id
        #   web
        if ($msubid) {
            $self->{'subid'} = $msubid;
            $self->{'spec'}  = $mrefid . "#" . $msubid;
        }
        $self->{'flags'} = $mflags if ($mflags);
        if ($mxprefid) {
            my ($mxpid, $mxpweb) = (reverse split(/\./, $mxprefid));
            $self->{'xpweb'}   = $mxpweb || $web;
            $self->{'xpid'}    = $mxpid;
            # SMELL should this always include the web, even if not
            # specified by the user?
            $self->{'xprefid'} = $self->{'xpweb'} . "." . $self->{'xpid'};
        }
        $self->{'xpsub'} = $mxpsub if ($mxpsub);
        $self->{'xpspec'}  = $self->{'xpweb'} . "." . $self->{'xpid'} . "#"
            . $self->{'xpsub'};
    }
    return bless ($self, $class);
}


# Create a new EntitySpec referring to the transport as defined in
# $self.  No checks are made to determine if $self actually contains a
# valid transport definition.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec
#   object reference (implicit using -> syntax).
#
# @return a new EntitySpec that refers to the transport as defined in $self.
sub deref {
    my ($self) = @_;
    my $newself = {
        'refid'      => $self->xprefid(),
        'spec'       => $self->xpspec(),
        'subid'      => $self->xpsub(),
        'id'         => $self->xpid(),
        'web'        => $self->xpweb(),
        'flags'      => "",
        'xprefid'    => "",
        'xpweb'      => "",
        'xpid'       => "",
        'xpsub'      => "",
        'xpspec'     => ""
    };
    return bless ($newself, ref($self));
}


################################
# ACCESSORS
################################

sub refid   { return $_[0]->{'refid'}; }
sub spec    { return $_[0]->{'spec'}; }
sub subid   { return $_[0]->{'subid'}; }
sub id      { return $_[0]->{'id'}; }
sub web     { return $_[0]->{'web'}; }
sub flags   { return $_[0]->{'flags'}; }
sub xprefid { return $_[0]->{'xprefid'}; }
sub xpweb   { return $_[0]->{'xpweb'}; }
sub xpid    { return $_[0]->{'xpid'}; }
sub xpsub   { return $_[0]->{'xpsub'}; }
sub xpspec  { return $_[0]->{'xpspec'}; }

sub macroSpec {
    return $_[0]->spec() . "#" . $_[0]->flags() . "#" . $_[0]->xpspec();
}

# returns the macro spec with, overriding the sub IDs with DEFAULT
sub macroSpecDefSub {
    return
        $_[0]->web() . "." . $_[0]->id() . "#DEFAULT#" . $_[0]->flags() . "#" .
        $_[0]->xpweb() . "." . $_[0]->xpid() . "#DEFAULT";
}


# Return an Graphviz-friendly macro spec string constructed for this entity.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec
#   object reference (implicit using -> syntax).
sub getGraphvizInstance {
    my ($self) = @_;
    my $rv = $self->web() . "_" . $self->id() . "_" . $self->subid();
    # turn all characters that are invalid for graphviz names into _
    $rv =~ s/[^A-Za-z0-9_]/_/g;
    return $rv;
}


################################
# DATA MANAGEMENT
################################

# @return true if the EntitySpec in $lhs matches that in $rhs, taking
#   DEFAULT IDs, sub-IDs and transport IDs into account.
sub match {
    my ($lhs,
        $rhs) = @_;
    return
        (($lhs->web() eq $rhs->web()) &&
         (($lhs->id() eq "DEFAULT") ||
          ($rhs->id() eq "DEFAULT") ||
          ($lhs->id() eq $rhs->id())) &&
         (($lhs->subid() eq "DEFAULT") ||
          ($rhs->subid() eq "DEFAULT") ||
          ($lhs->subid() eq $rhs->subid())) &&
         ($lhs->xpweb() eq $rhs->xpweb()) &&
         (($lhs->xpid() eq "DEFAULT") ||
          ($rhs->xpid() eq "DEFAULT") ||
          ($lhs->xpid() eq $rhs->xpid())) &&
         (($lhs->xpsub() eq "DEFAULT") ||
          ($rhs->xpsub() eq "DEFAULT") ||
          ($lhs->xpsub() eq $rhs->xpsub())));
}

# This method is the same as match, except that having "DEFAULT" as an
# ID will NOT be considered a match (unless both are DEFAULT).
# @return true if the EntitySpec in $lhs matches that in $rhs, taking
#   DEFAULT sub-IDs and transport IDs into account.
sub matchID {
    my ($lhs,
        $rhs,
        $ignoreTransport) = @_;
    return
        (($lhs->web() eq $rhs->web()) &&
         ($lhs->id() eq $rhs->id()) &&
         (($lhs->subid() eq "DEFAULT") ||
          ($rhs->subid() eq "DEFAULT") ||
          ($lhs->subid() eq $rhs->subid())) &&
         ($ignoreTransport ||
          ($lhs->xpweb() eq $rhs->xpweb()) &&
          (($lhs->xpid() eq "DEFAULT") ||
           ($rhs->xpid() eq "DEFAULT") ||
           ($lhs->xpid() eq $rhs->xpid())) &&
          (($lhs->xpsub() eq "DEFAULT") ||
           ($rhs->xpsub() eq "DEFAULT") ||
           ($lhs->xpsub() eq $rhs->xpsub()))));
}


# Create a hash of EntitySpec objects from a hash of Entity objects.
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec
#   object reference (implicit using -> syntax).
# @param[in] $hash a hash reference containing Entity object references.
# @return a hash of EntitySpec objects.
sub specHash {
    my ($class,
        $hash) = @_;
    my %rv = map { $_ => $class->new($_,$hash->{$_}->web()) } keys %{ $hash };
    return %rv;
}


# Match an entity spec against a hash of EntitySpec object references.
# DEFAULT as an ID will not be considered a wild-card match.
sub matchHash {
    my ($self,
        $hash,
        $ignoreTransport) = @_;
    return 1 unless defined($hash);
    foreach my $key (keys %{ $hash }) {
        return 1 if ($self->matchID($hash->{$key}, $ignoreTransport));
    }
    return 0;
}

1;
