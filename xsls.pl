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
	{ $return = $item[1]; 1 }

item		: "<!--" <commit> comment
		| "!!" <commit> exclam_double
		| "!{" <commit> exclam_xpath
		| "!" name <commit> exclam_name
		| "<%" <commit> instruction "%>"
	{ $return = $item{instruction}; 1 }
		| "<" name attrs ">" <commit> item(s?) "</" name ">"
	{ $return = ::format_tag($item{name}, $item{attrs}, $item[6]); 1 }
		| "<" <commit> name attrs "/" ">"
	{ $return = ::format_tag($item{name}, $item{attrs}); 1 }
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
	{ $return = ::format_instruction(
		$item{instruction}, $item{attrs}, $item{body});
	1 }
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
	{ $return = "<!-- " . $item[1] . "-->"; 1; }

# special chars: ', ", {, }, \
# if used in text, they needs to be escaped with backslash

text		: quoted | unreserved | "'" | "\"" | "{"
quoted		: "\\" special
	{ $return = $item{special}; 1; }
special		: "'" | "\"" | "\\" | "{" | "}"
unreserved	: /[^'"\\{}]/

# shortcuts:
#
# !! for X:apply-templates
# !{xpath-expression} for X:value-of select="xpath-expression";
# !foo() for X:call-template name="foo"

# !root (path = { !{ substring($DIRNAME, 2) } })
# !root (path = "substring-after($path, '/')")

exclam_double	: value(?) params(?) attrs ";"
	{ $return = ::format_apply($item{value}, $item{params}, $item{attrs}); 1 }

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

params		: "(" param(s /,/) ")" 
	{ $return = $item[2]; 1 }
param		: name "=" value
		| name "=" <commit> "{" item(s) "}"
		| name

# instruction body
# ";" for empty body, "{ ... }" otherwise

body		: ";"
	{ $return = ""; }
		| "{" <commit> item(s?) "}"
	{ $return = join("\n", @{$item[3]}); 1 }

# special handling of some instructions
# X:if attribute is test=

xif		: value(?) attrs body "else" <commit> body
		| value(?) attrs body
		| <error>

# X:template name(params) = "match" {
# X:template name( bar="init", baz={markup} ) = "match" mode="some" {

xtemplate	: name(?) params(?) ( "=" value )(?)
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
	{ $return = ::format_instruction_value(
		"X:for-each", "select", $item{value}, $item{attrs}, $item{body});
	1 }
		| value attrs "," "X:sort" <commit> value attrs body

# X:sort select
# X:sort "@id"

xsort		: value attrs body
	{ $return = ::format_instruction_value(
		"X:sort", "select", $item{value}, $item{attrs}, $item{body});
	1 }

# X:when "position() = 1" { ... }

xwhen		: value attrs body
	{ $return = ::format_instruction_value(
		"X:when", "test", $item{value}, $item{attrs}, $item{body});
	1 }

# X:attribute "href" { ... }

xattribute	: value attrs body
	{ $return = ::format_instruction_value(
		"X:attribute", "name", $item{value}, $item{attrs}, $item{body});
	1 }

# X:output
# semicolon is optional

xoutput		: attrs body(?)
	{ $return = ::format_instruction(
		"X:output", $item{attrs}, $item{body});
	1 }

# "X:copy-of"
# semicolon is optional

xcopyof		: value attrs body(?)
	{ $return = ::format_instruction_value(
		"X:copy-of", "select", $item{value}, $item{attrs}, $item{body});
	1 }

# eof

eofile		: /^\Z/

EOF

###############################################################################

# helper formatting functions, used by grammar

sub format_instruction {
	my ($instruction, $attrs, $body) = @_;
	my $s = "<";

	$instruction =~ s/^X:/xsl:/;

	$s .= join(" ", $instruction, @{$attrs});

	if ($body) {
		$s .= ">\n" . $body . "\n</" . $instruction . ">\n";
	} else {
		$s .= "/>\n";
	}

	return $s;
}

sub format_instruction_value {
	my ($instruction, $name, $value, $attrs, $body) = @_;
	my $s = "<";

	if ($value) {
		push(@{$attrs}, "$name=$value");
	}

	return format_instruction($instruction, $attrs, $body);
}

sub format_tag {
	my ($tag, $attrs, $body) = @_;
	my $s = "\n<";

	$s .= join(" ", $tag, @{$attrs});

	$body = join("\n", @{$body});

	if ($body) {
		$s .= ">" . $body . "\n</" . $tag . ">\n";
	} else {
		$s .= "/>\n";
	}

	return $s;
}

sub format_apply {
	my ($select, $params, $attrs) = @_;
	my $s = "\n<";
	my $tag = "xsl:apply-templates";

	if ($select) {
		unshift "select=$select", @{$attrs};
	}

	$s .= join(" ", $tag, @{$attrs});

	if ($params) {
		$params = join("\n", @{$params});
		$s .= ">\n" . $params . "\n</" . $tag . ">\n";
	} else {
		$s .= "/>\n";
	}
}

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

#print Dumper($tree);
#print join("\n", @{$tree});

###############################################################################
###############################################################################
