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

#item		: "<!--" <commit> comment
#		| "!" <commit> shortcut
#		| "<%" <commit> instruction "%>"
#		| instruction_name <commit> 

item		: comment | instruction | shortcut
item_text	: comment | instruction | shortcut | text

# comments, <!-- ... -->
# not sure if it's something to be interpreted specially
# likely an artifact of our dump process

comment		: "<!--" <commit> /((?!-->).)*/ms "-->"
		{ $return = ""; 1; }

# special chars: ', ", {, }, \
# if used in text, they needs to be escaped with backslash

text		: quoted | unreserved | "'" | "\""
quoted		: "\\" special
		{ $return = $item{special}; 1; }
special		: "'" | "\"" | "\\" | "{" | "}"
unreserved	: /[^'"\\{}]/

# shortcuts:
#
# !{xpath-expression} for X:value-of select="xpath-expression";
# !! for X:apply-templates
# !foo() for X:call-template name="foo"

shortcut	: double_exclam | exclam_xpath | exclam_name
double_exclam	: "!!" <commit> param(s?) ";"
exclam_xpath	: "!{" <commit> text(s) "}"
exclam_name	: "!" <commit> name "(" param(s?) ")"
name		: /[a-z0-9_:-]+/i

param		: param_name "=" param_value
param_name	: /[a-z0-9_:-]+/i
param_value	: "\"" /[^"]*/ "\""

body		: ";"
		| "{" <commit> item_text(s?) "}"

instructions	: xstylesheet | xtransform
		| xattributeset | xattribute | xelement
		| xparam | xapplytemplates 
		| xforeach | xchoose | xwhen | xotherwise
		| xvalueof | xapplyimports | xnumber
		| xoutput | xinclude | ximport | xstripspace | xpreservespace
		| xcopyof | xcopy | xtext | xsort | xcomment
		| xprocessinginstruction | xdecimalformat | xnamespacealias
		| xkey | xfallback | xmessage

instruction	: "<%" instruction_simple "%>"
		| instruction_simple

instruction_simple : instructions <commit> param(s?) body
		| xif
		| xtemplate
		| xvar

# X:if parameter is test=

xif		: "X:if" param_value(?) param(s?) body "else" <commit> body
		| "X:if" <commit> param_value(?) param(s?) body

# X:template name(params) = "match" {
# X:template name( bar="init", baz={markup} ) = "match" mode="some" {

xtemplate	: "X:template" param_name(?) xtemplate_params(?)
		  xtemplate_match(?) param(s?) body
xtemplate_params: "(" xtemplate_param ("," xtemplate_param)(s?) ")"
xtemplate_param	: param_name ("=" param_value)(?)
xtemplate_match	: "=" param_value

# X:var LINK = "/article/@link";
# X:var year = { ... }

xvar		: xvar_name <commit> xvar_params
xvar_params	: param_name "=" param_value ";"
		| param_name "=" body
		| <error>

xvar_name	: "X:variable"
		| "X:var"

# normal instructions

xstylesheet	: "X:stylesheet"
xtransform	: "X:transform"
xattributeset	: "X:attribute-set"
xattribute	: "X:attribute"
xelement	: "X:element"
xvariable	: "X:variable"
xvar		: "X:var"
xparam		: "X:param"
xapplytemplates	: "X:apply-templates"
xforeach	: "X:for-each"
xchoose		: "X:choose"
xwhen		: "X:when"
xotherwise	: "X:otherwise"
xvalueof	: "X:value-of"
xapplyimports	: "X:apply-imports"
xnumber		: "X:number"
xoutput		: "X:output"
xinclude	: "X:include"
ximport		: "X:import"
xstripspace	: "X:strip-space"
xpreservespace	: "X:preserve-space"
xcopyof		: "X:copy-of"
xcopy		: "X:copy"
xtext		: "X:text"
xsort		: "X:sort"
xcomment	: "X:comment"
xprocessinginstruction : "X:processing-instruction"
xdecimalformat	: "X:decimal-format"
xnamespacealias	: "X:namespace-alias"
xkey		: "X:key"
xfallback	: "X:fallback"
xmessage	: "X:message"

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
