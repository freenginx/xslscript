#!/usr/bin/perl

# (C) Maxim Dounin

# Convert from XSLScript to XSLT.
# 
# Originally XSLScript was written by Paul Tchistopolskii.  It is believed
# to be mostly identical to XSLT, but uses shorter syntax.  Original
# implementation has major Java dependency, no longer supported and hard
# to find.
# 
# This code doesn't pretend to be a full replacement, but rather an attempt
# to provide functionality needed for nginx documentation.

###############################################################################

use warnings;
use strict;

use Parse::RecDescent;
use Getopt::Long;
use Data::Dumper qw/Dumper/;

###############################################################################

GetOptions(
	"trace!" => \$::RD_TRACE,
	"hint!" => \$::RD_HINT,
)
	or die "oops\n";

###############################################################################

my $grammar = <<'EOF';

# XSLTScript grammar, reconstructed

startrule	: item(s) eofile
		{ $return = $item[1] }

item		: "<!--" <commit> comment
		| "!!" <commit> double_exclam
		| "!{" <commit> exclam_xpath
		| "!" name <commit> exclam_name
		| "<%" <commit> instruction "%>"
		| "<" name attrs ">" <commit> item(s?) "</" name ">"
		| "<" <commit> name attrs "/" ">"
		| "X:variable" <commit> xvariable
		| "X:var" <commit> xvariable
		| "X:template" <commit> xtemplate
		| "X:if" <commit> xif
		| "X:param" <commit> xparam
		| "X:for-each" <commit> xforeach
		| "X:sort" <commit> xsort
		| "X:when" <commit> xwhen
		| "X:attribute" <commit> xattribute
		| "X:output" <commit> xoutput
		| "X:copy-of" <commit> xcopyof
		| instruction <commit> attrs body
		| text
		| <error>

# list of simple instructions

instruction	: "X:stylesheet"
		| "X:transform"
		| "X:attribute-set"
		| "X:element"
		| "X:apply-templates"
		| "X:choose"
		| "X:otherwise"
		| "X:value-of"
		| "X:apply-imports"
		| "X:number"
		| "X:include"
		| "X:import"
		| "X:strip-space"
		| "X:preserve-space"
		| "X:copy"
		| "X:text"
		| "X:comment"
		| "X:processing-instruction"
		| "X:decimal-format"
		| "X:namespace-alias"
		| "X:key"
		| "X:fallback"
		| "X:message"

# comments, <!-- ... -->
# not sure if it's something to be interpreted specially
# likely an artifact of our dump process

comment		: /((?!-->).)*/ms "-->"
		{ $return = ""; 1; }

# special chars: ', ", {, }, \
# if used in text, they needs to be escaped with backslash

text		: quoted | unreserved | "'" | "\"" | "{"
quoted		: "\\" special
		{ $return = $item{special}; 1; }
special		: "'" | "\"" | "\\" | "{" | "}"
unreserved	: /[^'"\\{}]/

# shortcuts:
#
# !{xpath-expression} for X:value-of select="xpath-expression";
# !! for X:apply-templates
# !foo() for X:call-template name="foo"

# !root (path = { !{ substring($DIRNAME, 2) } })
# !root (path = "substring-after($path, '/')")

double_exclam	: value(?) params attrs ";"

exclam_xpath	: xpath(s?) "}"
xpath		: /[^}'"]+/
		| /"[^"]*"/
		| /'[^']*'/

exclam_name	: params

# instruction attributes
# name="value"

attrs		: attr(s?)
attr		: name "=" value
name		: /[a-z0-9_:-]+/i
value		: /"[^"]*"/

# template parameters
# ( bar="init", baz={markup} )

params		: "(" param ("," param)(s?) ")"
		| ""
param		: name "=" value
		| name "=" <commit> "{" item(s) "}"
		| name

# instruction body
# ";" for empty body, "{ ... }" otherwise

body		: ";"
		| "{" <commit> item(s?) "}"

# special handling of some instructions
# X:if attribute is test=

xif		: value(?) attrs body "else" <commit> body
		| value(?) attrs body
		| <error>

# X:template name(params) = "match" {
# X:template name( bar="init", baz={markup} ) = "match" mode="some" {

xtemplate	: name(?) params ( "=" value )(?)
		  attrs body

# X:var LINK = "/article/@link";
# X:var year = { ... }
# semicolon is optional

xvariable	: name "=" value(?) attrs body
		| name "=" value(?)
		| <error>

# X:param XML = "'../xml'";
# X:param YEAR;

xparam		: name ("=" value)(?) attrs body

# X:for-each "section[@id and @name]" { ... }
# X:for-each "link", X:sort "@id" {

xforeach	: value attrs body
		| value attrs "," "X:sort" <commit> value attrs body

# X:sort select
# X:sort "@id"

xsort		: value attrs body

# X:when "position() = 1" { ... }

xwhen		: value attrs body

# X:attribute "href" { ... }

xattribute	: value attrs body

# X:output
# semicolon is optional

xoutput		: attrs body
		| attrs

# "X:copy-of"
# semicolon is optional

xcopyof		: value attrs body
		| value

# eof

eofile		: /^\Z/

EOF

###############################################################################

my $parser = Parse::RecDescent->new($grammar)
	or die "Failed to create parser.\n";

my $lines;

{
	local $/;
	$lines = <>;
}

my $tree = $parser->startrule($lines)
	or die "Failed to parse $ARGV.\n";

print Dumper($tree);

###############################################################################
###############################################################################
