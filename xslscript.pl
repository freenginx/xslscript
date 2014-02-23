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

my $dump = 0;

GetOptions(
	"trace!" => \$::RD_TRACE,
	"hint!" => \$::RD_HINT,
	"dump!" => \$dump,
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
		| "!" name <commit> params
	{ $return = [
		"X:call-template", "name", $item{name}, [],
		$item{params}
	]; 1 }
		| "<%" <commit> instruction "%>"
	{ $return = $item{instruction}; 1 }
		| "<" name attrs ">" <commit> item(s?) "</" name ">"
	{ $return = [ "tag", $item{name}, $item{attrs}, $item[6] ]; 1 }
		| "<" <commit> name attrs "/" ">"
	{ $return = [ "tag", $item{name}, $item{attrs} ]; 1 }
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
	{ $return = [ $item{instruction}, $item{attrs}, $item{body} ]; 1 }
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
	{ $return = ""; 1 }

# special chars: ', ", {, }, \
# if used in text, they needs to be escaped with backslash

text		: quoted | unreserved | "'" | "\"" | "{"
quoted		: "\\" special
	{ $return = $item{special}; 1; }
special		: "'" | "\"" | "\\" | "{" | "}"
unreserved	: /[^'"\\{}<\s]+\s*/

# shortcuts:
#
# !! for X:apply-templates
# !{xpath-expression} for X:value-of select="xpath-expression";
# !foo() for X:call-template name="foo"

# !root (path = { !{ substring($DIRNAME, 2) } })
# !root (path = "substring-after($path, '/')")

exclam_double	: value(?) params(?) attrs ";"
	{ $return = [
		"X:apply-templates", "select", $item[1][0], $item{attrs},
		$item[2][0]
	]; 1 }

exclam_xpath	: xpath "}"
	{ $return = [
		"X:value-of", "select", $item{xpath}, []
	]; 1 }
xpath		: /("[^"]*"|'[^']*'|[^}'"])*/ms

# instruction attributes
# name="value"

attrs		: attr(s?)
attr		: name "=" value
	{ $return = $item{name} . "=" . $item{value}; }
name		: /[a-z0-9_:-]+/i
value		: /"[^"]*"/

# template parameters
# ( bar="init", baz={markup} )

params		: "(" param(s? /,/) ")" 
	{ $return = $item[2]; 1 }
param		: name "=" value
	{ $return = [
		"X:with-param",
		"select", $item{value},
		"name", $item{name},
		[]
	]; 1 }
		| name "=" <commit> "{" item(s) "}"
	{ $return = [
		"X:with-param", "name", $item{name}, [],
		$item[5]
	]; 1 }
		| name
	{ $return = [
		"X:param", "name", $item{name}, []
	]; 1 }

# instruction body
# ";" for empty body, "{ ... }" otherwise

body		: ";"
	{ $return = ""; }
		| "{" <commit> item(s?) "}"
	{ $return = $item[3]; 1 }

# special handling of some instructions
# X:if attribute is test=

xif		: value body "else" <commit> body
	{ $return = [
		"X:choose", [], [
			[ "X:when", "test", $item[1], [], $item[2] ],
			[ "X:otherwise", [], $item[5] ]
		]
	]; 1 }
		| value attrs body
	{ $return = [
		"X:if", "test", $item{value}, $item{attrs}, $item{body},
	]; 1 }
		| attrs body
	{ $return = [
		"X:if", $item{attrs}, $item{body},
	]; 1 }
		| <error>

# X:template name(params) = "match" {
# X:template name( bar="init", baz={markup} ) = "match" mode="some" {

xtemplate	: name(?) params(?) ( "=" value )(?) attrs body
	{ $return = [
		"X:template", "name", $item[1][0], "match", $item[3][0],
		$item{attrs},
		[ ($item[2][0] ? @{$item[2][0]} : ()), @{$item{body}} ]
	]; 1 }

# X:var LINK = "/article/@link";
# X:var year = { ... }
# semicolon is optional

xvariable	: name "=" value attrs body
	{ $return = [
		"X:variable",
		"select", $item{value},
		"name", $item{name},
		$item{attrs}, $item{body}
	]; 1 }
		| name "=" attrs body
	{ $return = [
		"X:variable",
		"name", $item{name},
		$item{attrs}, $item{body}
	]; 1 }
		| name "=" value
	{ $return = [
		"X:variable",
		"select", $item{value},
		"name", $item{name},
		[]
	]; 1 }
		| name "=" 
	{ $return = [
		"X:variable",
		"name", $item{name},
		[]
	]; 1 }
		| <error>

# X:param XML = "'../xml'";
# X:param YEAR;

xparam		: name "=" value attrs body
	{ $return = [
		"X:param",
		"select", $item{value},
		"name", $item{name},
		$item{attrs}, $item{body}
	]; 1 }
		| name attrs body
	{ $return = [
		"X:param", "name", $item{name},
		$item{attrs}, $item{body}
	]; 1 }

# X:for-each "section[@id and @name]" { ... }
# X:for-each "link", X:sort "@id" {

xforeach	: value attrs body
	{ $return = [
		"X:for-each", "select", $item{value}, $item{attrs}, $item{body}
	]; 1 }
		| value attrs "," "X:sort" <commit> value attrs body
	{ $return = [
		"X:for-each", "select", $item[1], $item[2], [
			[ "X:sort", "select", $item[6], $item[7] ],
			@{$item{body}}
		]
	]; 1 }

# X:sort select
# X:sort "@id"

xsort		: value attrs body
	{ $return = [
		"X:sort", "select", $item{value}, $item{attrs}, $item{body}
	]; 1 }

# X:when "position() = 1" { ... }

xwhen		: value attrs body
	{ $return = [
		"X:when", "test", $item{value}, $item{attrs}, $item{body}
	]; 1 }

# X:attribute "href" { ... }

xattribute	: value attrs body
	{ $return = [
		"X:attribute", "name", $item{value}, $item{attrs}, $item{body}
	]; 1 }

# X:output
# semicolon is optional

xoutput		: attrs body(?)
	{ $return = [
		"X:output", undef, undef, $item{attrs}, $item{body}
	]; 1 }

# "X:copy-of"
# semicolon is optional

xcopyof		: value attrs body(?)
	{ $return = [
		"X:copy-of", "select", $item{value}, $item{attrs}, $item{body}
	]; 1 }

# eof

eofile		: /^\Z/

EOF

###############################################################################

sub format_tree {
	my ($tree, $indent) = @_;
	my $s = '';

	if (!defined $indent) {
		$indent = 0;
		$s .= '<?xml version="1.0" encoding="utf-8"?>' . "\n";
	}

	my $space = "   " x $indent;

	foreach my $el (@{$tree}) {
		if (!defined $el) {
			warn "Undefined element in output.\n";
			$s .= $space . "(undef)" . "\n";
			next;
		}

		if (not ref($el) && defined $el) {
			#$s .= $space . $el . "\n";
			$s .= $el;
			next;
		}

		die if ref($el) ne 'ARRAY';

		my $tag = $el->[0];

		if ($tag eq 'tag') {
			my (undef, $name, $attrs, $body) = @{$el};

			$s .= $space . "<" . join(" ", $name, @{$attrs});
			if ($body) {
				my $t = format_tree($body, $indent + 1);
				if ($t =~ /\n/) {
					$s .= ">\n" . $t
						. $space . "</$name>\n";
				} else {
					$s .= ">$t</$name>\n";
				}
			} else {
				$s .= "/>\n";
			}

			next;
		}

		if ($tag =~ m/^X:(.*)/) {
			my $name = "xsl:" . $1;
			my (undef, @a) = @{$el};
			my @attrs;

			while (@a) {
				last if ref($a[0]) eq 'ARRAY';
				my $name = shift @a;
				my $value = shift @a;
				next unless defined $value;
				$value = '"' . $value . '"'
					unless $value =~ /^"/;
				push @attrs, "$name=$value";
			}

			if ($name eq "xsl:stylesheet") {
				push @attrs, 'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"';
				push @attrs, 'version="1.0"';
			}

			my ($attrs, $body) = @a;
			$attrs = [ @{$attrs}, @attrs ];

			$s .= $space . "<" . join(" ", $name, @{$attrs});
			
			if ($body && scalar @{$body} > 0) {
				my $t = format_tree($body, $indent + 1);
				if ($t =~ /\n/) {
					$s .= ">\n" . $t
						. $space . "</$name>\n";
				} else {
					$s .= ">$t</$name>\n";
				}
			} else {
				$s .= "/>\n";
			}

			next;
		}

		$s .= format_tree($el, $indent + 1);
	}

	return $s;
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

if ($dump) {
	print Dumper($tree);
	exit(0);
}

print format_tree($tree);

###############################################################################
