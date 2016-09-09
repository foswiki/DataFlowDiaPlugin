# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin.pm#4 $

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

# finding syntax errors:
# perl -I/var/www/foswiki/lib -I/var/www/foswiki/lib/Foswiki/Infix -c /var/www/foswiki/lib/Foswiki/Plugins/DataFlowDiaPlugin.pm


=begin TML

---+ package Foswiki::Plugins::DataFlowDiaPlugin

Defines macros for graphing and data-mining information regarding data
flow in a design.

---++ Implementation Conventions

The interface between Foswiki and plug-ins is functional, as opposed
to object-oriented.  This functional interface is implemented in this
package, while the meat of the implementation for this plug-in is
implemented in Foswiki::Plugins::DataFlowDiaPlugin::DocManager.  This
latter package is an OO Perl implementation.

The following are general rules used in the implementation:
   * Classes will always have a new() method to instantiate themselves (Util being the exception as a collection of utility functions).
      * All Perl objects will be blessed hash references.
      * The new() methods must set hash keys to some initial value for all used keys, even if the value is undef.  This is as much for documentation as anything.
   * The following variable names will always carry the same meaning:
      * _$class_ - implicit parameter used by Perl in OO programming.  This is the name of the class, and is used in "constructor" methods.
      * _$self_ - implicit parameter used by Perl in OO programming.  This is a Perl reference to an instance of the class defining the method being called.
      * _$web_ - the relevant wiki web name (string) for a given operation.
      * _$defaultWeb_ - When constructing complete specification of a cross reference, this wiki web name (string) is used in the event a web is not explicitly specified in the cross reference (see Spec below).
      * _$topic_ - the relevant wiki topic name (string) for a given operation.  Does not include the wiki web.
      * _$entityType_ - a string representation of the entity being processed. This is the macro name stripped of all redundant text, e.g. LOCALE.  See Foswiki::Plugins::DataFlowDiaPlugin::DocManager.
      * _$macroAttrs_ - Each wiki macro has a set of parameters.  These parameters are turned from the wiki page text into a hash using Foswiki::Func::extractParameters() and passed to subroutines that need the information.  The following additional members are added to _$macroAttrs_
         * '_RAW', containing only the macro parameters
         * '_ORIG', containing the entire macro text
         * '_MACRONAME', containing the macro being processed, e.g. PROC
      * _$docManager_ - an instance of the Foswiki::Plugins::DataFlowDiaPlugin::DocManager class, one used per wiki/cgi session.
   * Variable/subroutine naming conventions.  These name fragments implications wrt their content and/or function.  These name fragments will generally be at the end of the subroutine or variable name.  When naming, the hind-most name fragment is the most relevant to the content, e.g. _$entityRef_ is a "Ref", not a Perl object reference to an Entity instance.
      * Element (or Elem) - refers to an XML::LibXML::Element object reference.
      * Entity - refers to an object reference to Foswiki::Plugins::DataFlowDiaPlugin::Entity, or (more commonly) to an object reference of derived classes.
      * Spec - a unique identifier for entities.  A "macro spec" is a formatted string used by macros, while an "entity spec" is a structured version (i.e. object reference to a class) of the same.
      * ID - a unique identifier (string) of an entity within a given wiki web.  This is a fragment of Spec, and also appears in Ref hashes.
      * Hash - a Perl hash.
      * Arr - a Perl array/list.

---+++ Error Handling

Classes defined for this plug-in use =die()= on error conditions.
These exceptions are handled in an =eval= block and turned into error
text for the wiki renderer.  See
Foswiki::Plugins::DataFlowDiaPlugin::DocManager::addMacroData for an
example.

---++ Coding Conventions

Due to the complexity of this implementation, the following choices
have been made in an attempt to make the code clearer and less prone
to error.

   * Classes are implemented as blessed hash references.
   * Hash members are always initialized to something (even if "undef") in the new method, to make clear what hash members are used in the class.
   * Hash members are only directly accessed when setting their values.  The exception is Foswiki::Attrs which doesn't follow this convention.
      * Setting the values of hash members should be done in the new method or in another method dedicated to setting that hash member.
      * This includes the implementation of the class itself, though obviously excludes the accessor methods themselves
   * Read access to hash members is provided by method definitions of the same name as the hash key.
      * Accessors or data management methods that are not direct read values in the internal hash may be named "get..." for distinction
   * Read/write access to hash members that are themselves hashes may be done with methods using optional parameters where each successive parameter is one additional layer of the onion, e.g. =$self->hash($top, $level1, $level2...)=
   * Methods in classes are organized into named sections in the following order:
      * CONSTRUCTORS - methods (e.g. new) that create and return a new object reference for this class
      * MACRO PROCESSING - methods that process Foswiki macro parameter data
      * XML PROCESSING - methods that process or produce XML::LibXML objects
      * ACCESSORS - methods that provide simple read or write access to the class' hash members
      * DATA MANAGEMENT - methods that perform more sophisticated read/write access to the class' internal data storage, i.e. methods that do additional data processing beyond reading and writing of values
      * TEXT PROCESING - methods associated with the production of formatted output as specified by the user
      * GRAPHVIZ PROCESSING - methods associated with the production of Graphviz descriptions
      * WIKI/WEB PROCESSING - methods associated with the production of HTML or wiki mark-up text (different from TEXT PROCESSING in that these methods are for internal functions rather than user-defined formats)
      * UTILITY SUBS - "static" methods that do not require an object reference and do not otherwise fit into any of the above categories

Any deviation from these conventions should be considered suspect and
not a license to ignore the convention in question :-)



=cut

package Foswiki::Plugins::DataFlowDiaPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(macroError isValidID genDotStart genDotEnd unique _debugWrite _debugDump _debugFuncStart _debugFuncEnd _debugFile);
use Foswiki::Plugins::DataFlowDiaPlugin::DocManager;
use Scalar::Util;

use version; our $VERSION = version->declare("v2.0.1");
our $RELEASE = '2.0.1';
our $SHORTDESCRIPTION = 'Generate data flow diagrams';
our $NO_PREFS_IN_TOPIC = 1;

#
# General plugin information
#
# ... nothing.

#
# Plugin settings passed in URL or by preferences
#
our $debugDefault;          # Debug mode
our $debugUnitTests;        # Debug output to STDERR for unit tests
our $dotTagDefault;         # options for DirectedGraphPlugin <dot> tag
our $graphDefault;          # Graphviz options for graph objects
our $edgeDefault;           # Graphviz options for edges
our $nodeDefault;           # Graphviz options for nodes
our $procNodeDefault;       # Graphviz node options for non-deprecated procs
our $dataNodeDefault;       # Graphviz node options for non-deprecated data
our $procNodeDepDefault;    # Graphviz node options for deprecated procs
our $dataNodeDepDefault;    # Graphviz node options for deprecated data
our $deprecatedMarkup;      # HTML mark-up tag for deprecated entities

#
# Internal constants
#

#
# Internal variables/flags
#

#
# Module storage
#
my $docManager;

=begin TML

---++ initPlugin($topic, $web, $user, $installWeb) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in
     (usually the same as =$Foswiki::cfg{SystemWebName}=)

*REQUIRED*

Called to initialize the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using =Foswiki::Func::writeWarning= and return 0. In this case
%<nop>FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # Get plugin debug flag
    $debugDefault =
	Foswiki::Func::getPreferencesFlag('DATAFLOWDIAPLUGIN_DEBUG');
    $debugUnitTests = 0; # only specified by hand in unit test code
    # Get the default options for the DirectedGraphPlugin <dot> tag
    $dotTagDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_DOTTAGOPTS')
        || 'inline="svg" map="1" vectorformats="dot"';
    # Get defaults for graphviz entity types (graph, edge, node)
    $graphDefault = 
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_GRAPHDEFAULTS')
        || 'rankdir="LR",labelloc="t"';
    $edgeDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_EDGEDEFAULTS')
        || "fontsize=8";
    $nodeDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_NODEDEFAULTS')
        || "style=filled,fontsize=9,fillcolor=white";
    # Get graphviz node defaults
    $procNodeDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_PROCDEFAULTS')
        || "shape=\"ellipse\"";
    $dataNodeDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_DATADEFAULTS')
        || "shape=\"note\"";
    $procNodeDepDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_DEPPROCDEFAULTS')
        || "shape=\"ellipse\",fillcolor=red";
    $dataNodeDepDefault =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_DEPDATADEFAULTS')
        || "shape=\"note\",fillcolor=red";
    $deprecatedMarkup =
	Foswiki::Func::getPreferencesValue('DATAFLOWDIAPLUGIN_DEPMARKUP')
        || "del";

    unless ($deprecatedMarkup =~ m/^[a-zA-Z][a-zA-Z0-9_]*$/) {
        Foswiki::Func::writeWarning("Invalid HTML markup DATAFLOWDIAPLUGIN_DEPMARKUP = \"$deprecatedMarkup\"");
        return 0;
    }

    _debugWrite("DataFlowDiaPlugin::initPlugin===============================");

    $docManager = Foswiki::Plugins::DataFlowDiaPlugin::DocManager->new();

    # Plugin correctly initialized
    return 1;
}


=begin TML

---++ finishPlugin()

Called when a CGI session is completed.  Free the memory used by the
Foswiki::Plugins::DataFlowDiaPlugin::DocManager and save any updated
data in the process.

=cut

sub finishPlugin {
    $docManager->saveDocs();
    _debugWrite("final # of macro uses: " . $docManager->{'graphNum'});
    _debugWrite("DataFlowDiaPlugin::finishPlugin=============================");
    undef $docManager;
}


=begin TML

---++ commonTagsHandler($text, $topic, $web, $included, $meta)
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$included= - Boolean flag indicating whether the handler is
     invoked on an included topic
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called by the code that expands %<nop>MACROS% syntax in
the topic body and in form fields. It may be called many times while
a topic is being rendered.

This plugin implements processing in commonTagsHandler instead of
registered macros so that certain macros defining entities can be
pre-processed to populate the data store prior to attempts to render.
That is, definition macros are processed to store the metadata, then
definition macros and render-only macros are processed in order to
produce the desired rendering.

=cut

sub commonTagsHandler {
    my ( $text, $topic, $web, $included, $meta ) = @_;

    if ($included)
    {
	# do nothing if being processed as an include, wait for the
	# main topic to be rendered
	return;
    }
    # ignore contexts where attempting to process the macros would
    # result in inappropriate removal of metadata
    my $contextHashRef = Foswiki::Func::getContext();
    if ($contextHashRef->{view}) {
	my $query = Foswiki::Func::getRequestObject();
	if (Foswiki::isTrue($query->param('raw'))) {
	    return;
	}
    } elsif (($contextHashRef->{preview}) ||
	     ($contextHashRef->{save})) {
	# continue processing
    } else {
	# ignore all contexts other than view, preview and save
	return;
    }

    # Make sure the XML store is loaded.  If all macros have been
    # removed from a topic, we need this to remove the entity defs
    # from the store.
    $docManager->loadDocs($web, $topic);
    # pre-process data definition macros for storage
    my $regexMacro = qr/\%DFD(PROC|DATA|TRANSPORT|LOCALE|GROUP){([^{}%]*)}%/;
    # use $text for non-modifying, or $_[0] for reference to modify
    $_[0] =~ s/$regexMacro/&_preProcess($1,$2,$topic,$web,$meta)/gise;

    # render macros
    $regexMacro = qr/\%DFD(PROC|DATA|TRANSPORT|LOCALE|GROUP|SEARCH|CONNECT){([^{}%]*)}%/;
    $_[0] =~ s/$regexMacro/&_postProcess($1,$2,$topic,$web,$meta)/gise;
}



#################################
# Remaining Foswiki Plugin subs #
#################################


=begin TML

---++ _preProcess($macro, $attrs, $topic, $web, $meta)
   * =$macro= - the stripped name of the macro ("%", "DFD" and "{...}" removed)
   * =$attrs= - the macro parameters as a string, i.e. the text between {}
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=

This sub is meant to be called by commonTagsHandler to perform
pre-processing of entity macros to populate the internal data storage.

=cut

sub _preProcess {
    my ($macro, $attrs, $topic, $web, $meta) = @_;
    my %params = Foswiki::Func::extractParameters($attrs);

    return "missing-ID" unless $params{'id'};
    return "invalid-ID" unless isValidID($params{'id'});

    $params{'_RAW'} = $attrs;
    $params{'_ORIG'} = "\%DFD" . $macro . "{" . $attrs . "}%";

    my $rv = $docManager->addMacroData($web, $topic, $macro, \%params);
    return $rv;
}


=begin TML

---++ _postProcess($macro, $attrs, $topic, $web, $meta)
   * =$macro= - the stripped name of the macro ("%", "DFD" and "{...}" removed)
   * =$attrs= - the macro parameters as a string, i.e. the text between {}
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=

This sub is meant to be called by commonTagsHandler to perform
post-processing of macros for rendering.

=cut

sub _postProcess {
    my ($macro, $attrs, $topic, $web, $meta) = @_;
    my %params = Foswiki::Func::extractParameters($attrs);
    my $rv = "";

    $params{'_RAW'} = $attrs;
    $params{'_ORIG'} = "\%DFD" . $macro . "{" . $attrs . "}%";
    $params{'_MACRONAME'} = $macro;

    if ($params{'id'}) {
        # create a fully-qualified entity spec for this macro's entity
        # ID for use by subroutines.
        $params{'identityspec'} =
            Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                $params{'id'}, $web);
    }

    if ($debugDefault) {
        $rv .= "<nop>DataFlowDiaPlugin rendering macro<br/><pre>" . $params{'_ORIG'} . "</pre>\n\n";
    }

    $rv .= $docManager->renderMacro($web, $topic, $macro, \%params);
    return $rv;
}

1;
