# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/LocaleTransport.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport

Class for storing information about associated locale and transport
pairs.  Used by Locale for storing interconnection information.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec;
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes);

################################
# CONSTRUCTORS
################################


# Create a new LocaleTransport object.
#
# @param[in] $class The name of the class being instantiated.
# @param[in] $defaultWeb The Wiki web to use if one is not explicitly
#   specified in the data or transport macro specs.
# @param[in] $cnctSpec The macro spec for the locale connection
#   (locale '|' transport).
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a LocaleTransport object.
sub new {
    my ($class,
        $defaultWeb,
        $cnctSpec,
        $docManager) = @_;

    die ("invalid locale connection specification \"$cnctSpec\"\n")
        if ($cnctSpec !~ /^[^\|]+\|[^\|]+$/);

    my ($localeMacroSpec, $xportMacroSpec) = split(/\|/, $cnctSpec);

    my ($localeEntitySpec, $localeEntity) = $docManager->getEntityFromMacroSpec(
        $ENTITYTYPE_LOCALE,
        $defaultWeb, $localeMacroSpec);

    my ($xportEntitySpec, $xportEntity) = $docManager->getEntityFromMacroSpec(
        $ENTITYTYPE_XPORT,
        $defaultWeb, $xportMacroSpec);

    my $self = {
        'locale'           => $localeEntity,
        'localeMacroSpec'  => $localeEntitySpec->spec(),
        'localeEntitySpec' => $localeEntitySpec,
        'xport'            => $xportEntity,
        'xportMacroSpec'   => $xportEntitySpec->spec(),
        'xportEntitySpec'  => $xportEntitySpec,
        'macroSpec'        => $localeEntitySpec->spec() . "|" .
            $xportEntitySpec->spec()
    };

    return bless ($self, $class);
}


# Create a new LocaleTransport object from an XML::LibXML::Element.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   LocaleTransport definition.
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a LocaleTransport object.
sub newXML {
    my ($class,
        $xmlElem,
        $docManager) = @_;

    my ($localeEntitySpec, $localeEntity) = $docManager->getEntityFromXML(
        $ENTITYTYPE_LOCALE,
        $xmlElem);

    # The above call should have stored the Transport EntitySpec into
    # localeEntitySpec, so use that for searching.
    my $xportEntity = $docManager->getEntity(
        $ENTITYTYPE_XPORT,
        $localeEntitySpec->xpweb(),
        $localeEntitySpec->xpid());

    my $self = {
        'locale'          => $localeEntity,
        'localeMacroSpec' => $localeEntitySpec->spec(),
        'localeEntitySpec' => $localeEntitySpec,
        'xport'           => $xportEntity,
        'xportMacroSpec'  => $localeEntitySpec->xpspec(),
        'xportEntitySpec' => $localeEntitySpec->deref(),
        'macroSpec'       => $localeEntitySpec->spec() . "|" .
            $localeEntitySpec->xpspec()
    };

    return bless ($self, $class);
}


################################
# XML PROCESSING
################################

# Create an XML::LibXML::Element representing this LocaleTransport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing the
#   LocaleTransport.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing this LocaleTransport.
sub toXML {
    my ($self,
        $elementName,
        $inclInh) = @_;
    my $rv = $self->{'locale'}->toXMLRef(
        $elementName, $self->{'localeMacroSpec'}, $inclInh);
    my $xportXMLElem = $self->{'xport'}->toXMLRef(
        "xport", $self->{'xportMacroSpec'}, $inclInh);
    $rv->addChild($xportXMLElem);
    return $rv;
}


################################
# ACCESSORS
################################


sub localeEntity     { return $_[0]->{'locale'}; }
sub localeMacroSpec  { return $_[0]->{'localeMacroSpec'}; }
sub localeEntitySpec { return $_[0]->{'localeEntitySpec'}; }
sub xportEntity      { return $_[0]->{'xport'}; }
sub xportMacroSpec   { return $_[0]->{'xportMacroSpec'}; }
sub xportEntitySpec  { return $_[0]->{'xportEntitySpec'}; }
sub macroSpec        { return $_[0]->{'macroSpec'}; }


################################
# DATA MANAGEMENT
################################

# A Locale Entity creates instances of the LocaleTransport class in
# order to maintain a list of cross-references.  This function does
# the opposite.  Consider:
#  Locale X is connected to Locale Y via Transport A.
#  This function tells Locale Y that Locale X connects to it via Transport A.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport
#   object reference (implicit using -> syntax).
# @param[in] $localeEntity The Locale that connects to this
#   LocaleTransport (Locale X in the above example).
sub reverseReferences {
    my ($self,
        $localeEntity) = @_;
    my $les = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newEntity(
        $localeEntity);
    my $newLT = {
        'locale'          => $localeEntity,
        'localeMacroSpec' => $localeEntity->getMacroSpec(),
        'localeEntitySpec' => $les,
        'xport'           => $self->{'xport'},
        'xportMacroSpec'  => $self->{'xportMacroSpec'},
        # SMELL safe to copy by reference?
        'xportEntitySpec' => $self->{'xportEntitySpec'},
        'macroSpec'       => $localeEntity->getMacroSpec() . "|" .
            $self->{'xportMacroSpec'}
    };
    $self->{'locale'}->connectFrom(bless($newLT, ref($self)));
    # only reverse-associate transports with the locales that
    # explicitly use them, i.e. those where "connectedFrom" explicitly
    # names the locale.
    # If for some reason the "connectedTo" locales are desired, use a
    # different hash key in Transport.pm than "locales".
    $self->{'xport'}->addLocale($localeEntity);
    undef $newLT;
    undef $les;
}


# Removes connections to the Locale Entity in this LocaleTransport as
# created by reverseReferences.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport
#   object reference (implicit using -> syntax).
# @param[in] $localeEntity The Locale that connects to this
#   LocaleTransport (Locale X in the above example).
sub purgeReverse {
    my ($self,
        $localeEntity) = @_;
    # remove back references to localeEntity from locale and xport both
    my $les = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newEntity(
        $localeEntity);
    my $newLT = {
        'locale'          => $localeEntity,
        'localeMacroSpec' => $localeEntity->getMacroSpec(),
        'localeEntitySpec' => $les,
        'xport'           => $self->{'xport'},
        'xportMacroSpec'  => $self->{'xportMacroSpec'},
        # SMELL safe to copy by reference?
        'xportEntitySpec' => $self->{'xportEntitySpec'},
        'macroSpec'       => $localeEntity->getMacroSpec() . "|" .
            $self->{'xportMacroSpec'}
    };
    $self->{'locale'}->disconnectFrom(bless($newLT, ref($self)));
    $self->{'xport'}->purgeLocale($localeEntity);
    undef $newLT;
    undef $les;
}


# @return true if the localeEntitySpec in $self matches that in
#   $locEntitySpec, taking DEFAULT IDs, sub-IDs and transport IDs into
#   account.
sub matchLocale {
    my ($self,
        $locEntitySpec) = @_;
    return $self->localeEntitySpec()->match($locEntitySpec);
}


# @return true if the xportEntitySpec in $self matches that in
#   $xportEntitySpec, taking DEFAULT IDs, sub-IDs and transport IDs
#   into account.
sub matchXport {
    my ($self,
        $xportEntitySpec) = @_;
    return $self->xportEntitySpec()->match($xportEntitySpec);
}

1;
