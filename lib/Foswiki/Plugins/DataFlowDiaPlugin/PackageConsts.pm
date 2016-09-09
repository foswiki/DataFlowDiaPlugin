# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/PackageConsts.pm#2 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts

Defines "constant" values used throughout the plug-in.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts;

use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw($ROOTNAME_DATA $NODENAME_DATA $ROOTNAME_LOCALE 
 $NODENAME_LOCALE $ROOTNAME_PROC $NODENAME_PROC $ROOTNAME_XPORT $NODENAME_XPORT
 $ROOTNAME_GROUP $NODENAME_GROUP 
 $ENTITYTYPE_PROC $ENTITYTYPE_DATA $ENTITYTYPE_XPORT $ENTITYTYPE_LOCALE
 $ENTITYTYPE_GROUP
 $CLASS_DATA $CLASS_LOCALE $CLASS_PROC $CLASS_XPORT $CLASS_GROUP
 $DIR_FWD $DIR_BACK $DIR_BOTH
 %LOOKUP_ENTITY %LOOKUP_NODE %LOOKUP_ROOT
 @ENTITY_PROC_ORDER);
our %EXPORT_TAGS = (
    'xml' => [ qw( $ROOTNAME_DATA $NODENAME_DATA $ROOTNAME_LOCALE
 $NODENAME_LOCALE $ROOTNAME_PROC $NODENAME_PROC $ROOTNAME_XPORT
 $NODENAME_XPORT $ROOTNAME_GROUP $NODENAME_GROUP ) ],
    'etypes' => [ qw( $ENTITYTYPE_PROC $ENTITYTYPE_DATA $ENTITYTYPE_XPORT
 $ENTITYTYPE_LOCALE $ENTITYTYPE_GROUP @ENTITY_PROC_ORDER ) ],
    'class' => [ qw( $CLASS_DATA $CLASS_LOCALE $CLASS_PROC $CLASS_XPORT
 $CLASS_GROUP ) ],
    'dirs' => [ qw( $DIR_FWD $DIR_BACK $DIR_BOTH ) ],
    'lookup' => [ qw( %LOOKUP_ENTITY %LOOKUP_NODE %LOOKUP_ROOT ) ],
    );

our $ROOTNAME_DATA   = "datacrossref";   # data type root node name
our $NODENAME_DATA   = "data";           # data type element node name
our $ROOTNAME_LOCALE = "localecrossref"; # locale root node name
our $NODENAME_LOCALE = "locale";         # locale element node name
our $ROOTNAME_PROC   = "proccrossref";   # process root node name
our $NODENAME_PROC   = "proc";           # process element node name
our $ROOTNAME_XPORT  = "xportcrossref";  # transport root node name
our $NODENAME_XPORT  = "xport";          # transport element node name
our $ROOTNAME_GROUP  = "groupcrossref";  # group root node name
our $NODENAME_GROUP  = "group";          # group element node name

# Entity Types
our $ENTITYTYPE_PROC   = "PROC";
our $ENTITYTYPE_DATA   = "DATA";
our $ENTITYTYPE_XPORT  = "TRANSPORT";
our $ENTITYTYPE_LOCALE = "LOCALE";
our $ENTITYTYPE_GROUP  = "GROUP";

# class names
our $CLASS_DATA   = 'Foswiki::Plugins::DataFlowDiaPlugin::DataType';
our $CLASS_LOCALE = 'Foswiki::Plugins::DataFlowDiaPlugin::Locale';
our $CLASS_PROC   = 'Foswiki::Plugins::DataFlowDiaPlugin::Process';
our $CLASS_XPORT  = 'Foswiki::Plugins::DataFlowDiaPlugin::Transport';
our $CLASS_GROUP  = 'Foswiki::Plugins::DataFlowDiaPlugin::Group';

our $DIR_FWD  = 1;
our $DIR_BACK = 2;
our $DIR_BOTH = 3;


# Look-up table by Entity Type (see above) for a list of:
#   Entity class name
#   XML root node name
#   XML item node name
our %LOOKUP_ENTITY = (
    $ENTITYTYPE_PROC => [
        $CLASS_PROC,
        $ROOTNAME_PROC,
        $NODENAME_PROC
    ],
    $ENTITYTYPE_DATA => [
        $CLASS_DATA,
        $ROOTNAME_DATA,
        $NODENAME_DATA
    ],
    $ENTITYTYPE_XPORT => [
        $CLASS_XPORT,
        $ROOTNAME_XPORT,
        $NODENAME_XPORT
    ],
    $ENTITYTYPE_LOCALE => [
        $CLASS_LOCALE,
        $ROOTNAME_LOCALE,
        $NODENAME_LOCALE
    ],
    $ENTITYTYPE_GROUP => [
        $CLASS_GROUP,
        $ROOTNAME_GROUP,
        $NODENAME_GROUP
    ],
    );

# Look-up table to find an Entity Type string from an XML item node name
our %LOOKUP_NODE = (
    $NODENAME_PROC   => $ENTITYTYPE_PROC,
    $NODENAME_DATA   => $ENTITYTYPE_DATA,
    $NODENAME_XPORT  => $ENTITYTYPE_XPORT,
    $NODENAME_LOCALE => $ENTITYTYPE_LOCALE,
    $NODENAME_GROUP  => $ENTITYTYPE_GROUP,
);

# Look-up table to find an Entity Type string from an XML root node name
our %LOOKUP_ROOT = (
    $ROOTNAME_PROC   => $ENTITYTYPE_PROC,
    $ROOTNAME_DATA   => $ENTITYTYPE_DATA,
    $ROOTNAME_XPORT  => $ENTITYTYPE_XPORT,
    $ROOTNAME_LOCALE => $ENTITYTYPE_LOCALE,
    $ROOTNAME_GROUP  => $ENTITYTYPE_GROUP,
);

# Entity processing order.
# These must be in order of dependency. 1st doc must have no
# dependencies, and so on.
our @ENTITY_PROC_ORDER = (
    $ENTITYTYPE_GROUP,
    $ENTITYTYPE_XPORT,
    $ENTITYTYPE_LOCALE,
    $ENTITYTYPE_DATA,
    $ENTITYTYPE_PROC,
    );

1;
