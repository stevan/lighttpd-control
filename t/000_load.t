#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;

BEGIN {
    use_ok('Lighttpd::Control');
}
