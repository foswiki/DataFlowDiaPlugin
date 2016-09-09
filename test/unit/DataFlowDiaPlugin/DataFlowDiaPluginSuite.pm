package DataFlowDiaPluginSuite;

use strict;
use warnings;

use Unit::TestSuite;
our @ISA = 'Unit::TestSuite';

sub name { 'DataFlowDiaPluginSuite' }

# List the modules that contain the extension-specific tests you
# want to run. These tests are run when you 'perl build.pl test'
sub include_tests { qw(DataFlowDiaPluginTests PairedEntityTests
 DataFlowDiaPluginRenderTests DataFlowDiaPluginStoreTests) }

1;
