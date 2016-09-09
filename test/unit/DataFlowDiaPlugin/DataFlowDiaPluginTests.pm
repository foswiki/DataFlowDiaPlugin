# $Id: //foswiki-dfd/rel2_0_1/test/unit/DataFlowDiaPlugin/DataFlowDiaPluginTests.pm#2 $

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

use strict;
use warnings;

package DataFlowDiaPluginTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;
use Foswiki;
use CGI;
use XML::LibXML;

use Foswiki::Plugins::DataFlowDiaPlugin::DocManager;

# full syntax is web.id#subid#flags#xpweb.xpid#xpsubid
my $unspec = "DEFAULT";
my $defaultWeb = "DaDefaultWeb";
# Could use the supplied test web but we're not actually doing
# anything but parsing strings so it doesn't really matter.
my ($web, $id, $subid, $flags, $xpweb, $xpid, $xpsubid) =
    ("TestWeb", "test_id", "test_subid", "test_flags",
     "XportWeb", "xport_id", "xport_subid");

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

# Set up the test fixture
sub set_up {
    my $this = shift;
    $this->SUPER::set_up();
    # BUG shouldn't this be set up in FoswikiFnTestCase?
    $Foswiki::Plugins::SESSION = $this->{session};
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

sub test_EntitySpec {
    my $this = shift;
    my $entityID = "simple";
    # construct from minimal macro spec, i.e. ID only
    my $es1 = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $entityID,
        $this->{test_web});
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es1 }) {
        $this->assert_not_null(
            $es1->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $this->assert_str_equals($entityID, $es1->id());
    $this->assert_str_equals($unspec,   $es1->subid());
    $this->assert_str_equals($this->{test_web}, $es1->web());
    $this->assert_str_equals("",        $es1->flags());
    $this->assert_str_equals($this->{test_web}, $es1->xpweb());
    $this->assert_str_equals($unspec,   $es1->xpid());
    $this->assert_str_equals($unspec,   $es1->xpsub());


    # use a full macro spec
    my $es2 = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $this->{test_web} . "." . $entityID . "#subid##" . $this->{test_web}
        . ".xport#subxport",
        "BrokenWeb");
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es2 }) {
        $this->assert_not_null(
            $es2->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $this->assert_str_equals($entityID,  $es2->id());
    $this->assert_str_equals("subid",    $es2->subid());
    $this->assert_str_equals($this->{test_web}, $es2->web());
    $this->assert_str_equals("",         $es2->flags());
    $this->assert_str_equals($this->{test_web}, $es2->xpweb());
    $this->assert_str_equals("xport",    $es2->xpid());
    $this->assert_str_equals("subxport", $es2->xpsub());
    $this->assert($es1->match($es2), "EntitySpec 1 and 2 do not match");


    # Use a full macro spec.  Changes subid which should not match es2
    # but should still match es1.
    my $es3 = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $this->{test_web} . "." . $entityID . "#dibus##" . $this->{test_web}
        . ".xport#subxport",
        "BrokenWeb");
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es3 }) {
        $this->assert_not_null(
            $es3->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $this->assert_str_equals($entityID,  $es3->id());
    $this->assert_str_equals("dibus",    $es3->subid());
    $this->assert_str_equals($this->{test_web}, $es3->web());
    $this->assert_str_equals("",         $es3->flags());
    $this->assert_str_equals($this->{test_web}, $es3->xpweb());
    $this->assert_str_equals("xport",    $es3->xpid());
    $this->assert_str_equals("subxport", $es3->xpsub());
    $this->assert($es1->match($es3), "EntitySpec 1 and 3 do not match");
    $this->assert(!$es2->match($es3), "EntitySpec 2 and 3 match");

    # Make an EntitySpec using XML. Should match es1 and es2 but not es3
    my $xmlElem = XML::LibXML::Element->new("test");
    $xmlElem->setAttribute("web", $this->{test_web});
    $xmlElem->setAttribute("id", $entityID);
    $xmlElem->setAttribute("subid", "subid");
    my $es4 = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newXML($xmlElem);
    undef $xmlElem;
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es4 }) {
        $this->assert_not_null(
            $es4->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $this->assert_str_equals($entityID, $es4->id());
    $this->assert_str_equals("subid",   $es4->subid());
    $this->assert_str_equals($this->{test_web}, $es4->web());
    $this->assert_str_equals("",        $es4->flags());
    $this->assert_str_equals($this->{test_web}, $es4->xpweb());
    $this->assert_str_equals($unspec,   $es4->xpid());
    $this->assert_str_equals($unspec,   $es4->xpsub());
    $this->assert($es1->match($es4), "EntitySpec 1 and 4 do not match");
    $this->assert($es2->match($es4), "EntitySpec 2 and 4 do not match");
    $this->assert(!$es3->match($es4), "EntitySpec 3 and 4 match");

    # Make an EntitySpec using XML including a transport child
    # node. Should match es1, es2 and es4 but not es3
    $xmlElem = XML::LibXML::Element->new("test");
    $xmlElem->setAttribute("web", $this->{test_web});
    $xmlElem->setAttribute("id", $entityID);
    $xmlElem->setAttribute("subid", "subid");
    my $xportElem = XML::LibXML::Element->new("xport");
    $xportElem->setAttribute("web", $this->{test_web});
    $xportElem->setAttribute("id", "xport");
    $xportElem->setAttribute("subid", "subxport");
    $xmlElem->addChild($xportElem);
    my $es5 = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newXML($xmlElem);
    undef $xmlElem;
    undef $xmlElem;
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es5 }) {
        $this->assert_not_null(
            $es5->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $this->assert_str_equals($entityID,  $es5->id());
    $this->assert_str_equals("subid",    $es5->subid());
    $this->assert_str_equals($this->{test_web}, $es5->web());
    $this->assert_str_equals("",         $es5->flags());
    $this->assert_str_equals($this->{test_web}, $es5->xpweb());
    $this->assert_str_equals("xport",    $es5->xpid());
    $this->assert_str_equals("subxport", $es5->xpsub());
    $this->assert($es1->match($es5), "EntitySpec 1 and 5 do not match");
    $this->assert($es2->match($es5), "EntitySpec 2 and 5 do not match");
    $this->assert(!$es3->match($es5), "EntitySpec 3 and 5 match");
    $this->assert($es4->match($es5), "EntitySpec 4 and 5 do not match");

    undef $es1;
    undef $es2;
    undef $es3;
    undef $es4;
    undef $es5;

    # TODO check newEntity and deref
    # TODO more rigorous testing on matching transports
}

# Test matrix for parsing
#         1 2 3 4 5 6 7 8 9
# id      x x x x x x x x x
# web       x       x   x  
# subid       x            
# flags         x          
# xpid            x x x x x
# xpweb               x x  
# xpsub                   x


sub test_EntitySpec_parse_1 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $id, $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals("",                            $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($unspec,                       $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$unspec#$unspec", $es->xpspec());
}


sub test_EntitySpec_parse_2 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$web.$id", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals("$web.$id",                    $es->refid());
    $self->assert_str_equals("$web.$id#$unspec",            $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($web,                          $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals("",                            $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($unspec,                       $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$unspec#$unspec", $es->xpspec());
}


sub test_EntitySpec_parse_3 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id#$subid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$subid",      $es->spec());
    $self->assert_str_equals($subid,                        $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals("",                            $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($unspec,                       $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$unspec#$unspec", $es->xpspec());
}


sub test_EntitySpec_parse_4 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id##$flags", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals($flags,                        $es->flags());
    $self->assert_str_equals("",                            $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($unspec,                       $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$unspec#$unspec", $es->xpspec());
}


sub test_EntitySpec_parse_5 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id###$xpid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals($xpid,                         $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$xpid#$unspec",   $es->xpspec());
}


sub test_EntitySpec_parse_6 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$web.$id###$xpid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals("$web.$id",                    $es->refid());
    $self->assert_str_equals("$web.$id#$unspec",            $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($web,                          $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals($xpid,                         $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$xpid#$unspec",   $es->xpspec());
}


sub test_EntitySpec_parse_7 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id###$xpweb.$xpid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals("$xpweb.$xpid",                $es->xprefid());
    $self->assert_str_equals($xpweb,                        $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$xpweb.$xpid#$unspec",        $es->xpspec());
}


sub test_EntitySpec_parse_8 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id###$xpweb.$xpid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals("$xpweb.$xpid",                $es->xprefid());
    $self->assert_str_equals($xpweb,                        $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($unspec,                       $es->xpsub());
    $self->assert_str_equals("$xpweb.$xpid#$unspec",        $es->xpspec());
}


sub test_EntitySpec_parse_9 {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$id###$xpid#$xpsubid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals($id,                           $es->refid());
    $self->assert_str_equals("$defaultWeb.$id#$unspec",     $es->spec());
    $self->assert_str_equals($unspec,                       $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($defaultWeb,                   $es->web());
    $self->assert_str_equals("",                            $es->flags());
    $self->assert_str_equals($xpid,                         $es->xprefid());
    $self->assert_str_equals($defaultWeb,                   $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($xpsubid,                      $es->xpsub());
    $self->assert_str_equals("$defaultWeb.$xpid#$xpsubid",  $es->xpspec());
}


sub test_EntitySpec_deref {
    my $self = shift;
    my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        "$web.$id#$subid#$flags#$xpweb.$xpid#$xpsubid", $defaultWeb);
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es }) {
        $self->assert_not_null(
            $es->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals("$web.$id",                    $es->refid());
    $self->assert_str_equals("$web.$id#$subid",             $es->spec());
    $self->assert_str_equals($subid,                        $es->subid());
    $self->assert_str_equals($id,                           $es->id());
    $self->assert_str_equals($web,                          $es->web());
    $self->assert_str_equals($flags,                        $es->flags());
    $self->assert_str_equals("$xpweb.$xpid",                $es->xprefid());
    $self->assert_str_equals($xpweb,                        $es->xpweb());
    $self->assert_str_equals($xpid,                         $es->xpid());
    $self->assert_str_equals($xpsubid,                      $es->xpsub());
    $self->assert_str_equals("$xpweb.$xpid#$xpsubid",       $es->xpspec());

    my $es2 = $es->deref();
    # make sure EntitySpec has no undefined fields
    foreach my $key (sort keys %{ $es2 }) {
        $self->assert_not_null(
            $es2->{$key},
            "Hash member \"$key\" of EntitySpec expected to be defined");
    }
    # check other fields
    $self->assert_str_equals("$xpweb.$xpid",                $es2->refid());
    $self->assert_str_equals("$xpweb.$xpid#$xpsubid",       $es2->spec());
    $self->assert_str_equals($xpsubid,                      $es2->subid());
    $self->assert_str_equals($xpid,                         $es2->id());
    $self->assert_str_equals($xpweb,                        $es2->web());
    $self->assert_str_equals("",                            $es2->flags());
    $self->assert_str_equals("",                            $es2->xprefid());
    $self->assert_str_equals("",                            $es2->xpweb());
    $self->assert_str_equals("",                            $es2->xpid());
    $self->assert_str_equals("",                            $es2->xpsub());
    $self->assert_str_equals("",                            $es2->xpspec());
}

1;
