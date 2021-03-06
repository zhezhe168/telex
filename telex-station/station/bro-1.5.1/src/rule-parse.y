%{
/* $Id: rule-parse.y 5988 2008-07-19 07:02:12Z vern $ */

#include <stdio.h>
#include "RuleMatcher.h"

extern void begin_PS();
extern void end_PS();

Rule* current_rule = 0;
const char* current_rule_file = 0;
%}

%token TOK_COMP
%token TOK_DISABLE
%token TOK_DST_IP
%token TOK_DST_PORT
%token TOK_ENABLE
%token TOK_EVAL
%token TOK_EVENT
%token TOK_HEADER
%token TOK_IDENT
%token TOK_INT
%token TOK_IP
%token TOK_IP_OPTIONS
%token TOK_IP_OPTION_SYM
%token TOK_IP_PROTO
%token TOK_PATTERN
%token TOK_PATTERN_TYPE
%token TOK_PAYLOAD_SIZE
%token TOK_PROT
%token TOK_REQUIRES_SIGNATURE
%token TOK_REQUIRES_REVERSE_SIGNATURE
%token TOK_SIGNATURE
%token TOK_SAME_IP
%token TOK_SRC_IP
%token TOK_SRC_PORT
%token TOK_TCP_STATE
%token TOK_STRING
%token TOK_TCP_STATE_SYM
%token TOK_ACTIVE
%token TOK_BOOL
%token TOK_POLICY_SYMBOL

%type <str> TOK_STRING TOK_IDENT TOK_POLICY_SYMBOL TOK_PATTERN pattern string
%type <val> TOK_INT TOK_TCP_STATE_SYM TOK_IP_OPTION_SYM TOK_COMP
%type <val> integer ipoption_list tcpstate_list
%type <rule> rule
%type <bl> TOK_BOOL
%type <hdr_test> hdr_expr
%type <range> range rangeopt
%type <vallist> value_list
%type <mval> TOK_IP value
%type <prot> TOK_PROT
%type <ptype> TOK_PATTERN_TYPE

%union {
	Rule* rule;
	RuleHdrTest* hdr_test;
	maskedvalue_list* vallist;

	bool bl;
	int val;
	char* str;
	MaskedValue mval;
	RuleHdrTest::Prot prot;
	Range range;
	Rule::PatternType ptype;
}

%%

rule_list:
		rule_list rule
			{ rule_matcher->AddRule($2); }
	|
	;

rule:
		TOK_SIGNATURE TOK_IDENT
			{
			Location l(current_rule_file, rules_line_number+1, 0, 0, 0);
			current_rule = new Rule(yylval.str, l);
			}
		'{' rule_attr_list '}'
			{ $$ = current_rule; }
	;

rule_attr_list:
		rule_attr_list rule_attr
	|
	;

rule_attr:
		TOK_DST_IP TOK_COMP value_list
			{
			current_rule->AddHdrTest(new RuleHdrTest(
				RuleHdrTest::IP, 16, 4,
				(RuleHdrTest::Comp) $2, $3));
			}

	|	TOK_DST_PORT TOK_COMP value_list
			{ // Works for both TCP and UDP
			current_rule->AddHdrTest(new RuleHdrTest(
				RuleHdrTest::TCP, 2, 2,
				(RuleHdrTest::Comp) $2, $3));
			}

	|	TOK_EVAL { begin_PS(); } TOK_POLICY_SYMBOL { end_PS(); }
			{
			current_rule->AddCondition(new RuleConditionEval($3));
			}

	|	TOK_HEADER hdr_expr
			{ current_rule->AddHdrTest($2); }

	|	TOK_IP_OPTIONS ipoption_list
			{
			current_rule->AddCondition(
				new RuleConditionIPOptions($2));
			}

	|	TOK_IP_PROTO TOK_COMP TOK_PROT
			{
			int proto = 0;
			switch ( $3 ) {
			case RuleHdrTest::ICMP: proto = 1; break;
			case RuleHdrTest::IP: proto = 0; break;
			case RuleHdrTest::TCP: proto = 6; break;
			case RuleHdrTest::UDP: proto = 17; break;
			default:
				rules_error("internal_error: unknown protocol");
			}

			if ( proto )
				{
				maskedvalue_list* vallist = new maskedvalue_list;
				MaskedValue* val = new MaskedValue();

				val->val = proto;
				val->mask = 0xffffffff;
				vallist->append(val);

				current_rule->AddHdrTest(new RuleHdrTest(
					RuleHdrTest::IP, 9, 1,
					(RuleHdrTest::Comp) $2, vallist));
				}
			}

	|	TOK_IP_PROTO TOK_COMP value_list
			{
			current_rule->AddHdrTest(new RuleHdrTest(
				RuleHdrTest::IP, 9, 1,
				(RuleHdrTest::Comp) $2, $3));
			}

	|	TOK_EVENT string
			{ current_rule->AddAction(new RuleActionEvent($2)); }

	|	TOK_ENABLE TOK_STRING
			{ current_rule->AddAction(new RuleActionEnable($2)); }

	|	TOK_DISABLE TOK_STRING
			{ current_rule->AddAction(new RuleActionDisable($2)); }

	|	TOK_PATTERN_TYPE pattern
			{ current_rule->AddPattern($2, $1); }

	|	TOK_PATTERN_TYPE '[' rangeopt ']' pattern
			{
			if ( $3.offset > 0 )
				warn("Offsets are currently ignored for patterns");
			current_rule->AddPattern($5, $1, 0, $3.len);
			}

	|	TOK_PAYLOAD_SIZE TOK_COMP integer
			{
			current_rule->AddCondition(
				new RuleConditionPayloadSize($3, (RuleConditionPayloadSize::Comp) ($2)));
			}

	|	TOK_REQUIRES_SIGNATURE TOK_IDENT
			{ current_rule->AddRequires($2, 0, 0); }

	|	TOK_REQUIRES_SIGNATURE '!' TOK_IDENT
			{ current_rule->AddRequires($3, 0, 1); }

	|	TOK_REQUIRES_REVERSE_SIGNATURE TOK_IDENT
			{ current_rule->AddRequires($2, 1, 0); }

	|	TOK_REQUIRES_REVERSE_SIGNATURE '!' TOK_IDENT
			{ current_rule->AddRequires($3, 1, 1); }

	|	TOK_SAME_IP
			{ current_rule->AddCondition(new RuleConditionSameIP()); }

	|	TOK_SRC_IP TOK_COMP value_list
			{
			current_rule->AddHdrTest(new RuleHdrTest(
				RuleHdrTest::IP, 12, 4,
				(RuleHdrTest::Comp) $2, $3));
			}

	|	TOK_SRC_PORT TOK_COMP value_list
			{ // Works for both TCP and UDP
			current_rule->AddHdrTest(new RuleHdrTest(
				RuleHdrTest::TCP, 0, 2,
				(RuleHdrTest::Comp) $2, $3));
			}

	|	TOK_TCP_STATE tcpstate_list
			{
			current_rule->AddCondition(new RuleConditionTCPState($2));
			}

	|	TOK_ACTIVE TOK_BOOL
			{ current_rule->SetActiveStatus($2); }
	;

hdr_expr:
		TOK_PROT '[' range ']' '&' integer TOK_COMP value
			{
			maskedvalue_list* vallist = new maskedvalue_list;
			MaskedValue* val = new MaskedValue();

			val->val = $8.val;
			val->mask = $6;
			vallist->append(val);

			$$ = new RuleHdrTest($1, $3.offset, $3.len,
					(RuleHdrTest::Comp) $7, vallist);
			}

	|	TOK_PROT '[' range ']' TOK_COMP value_list
			{
			$$ = new RuleHdrTest($1, $3.offset, $3.len,
						(RuleHdrTest::Comp) $5, $6);
			}
	;

value_list:
		value_list ',' value
			{ $1->append(new MaskedValue($3)); $$ = $1; }
	|	value_list ',' TOK_IDENT
			{ id_to_maskedvallist($3, $1); $$ = $1; }
	|	value
			{
			$$ = new maskedvalue_list();
			$$->append(new MaskedValue($1));
			}
	|	TOK_IDENT
			{
			$$ = new maskedvalue_list();
			id_to_maskedvallist($1, $$);
			}
	;

value:
		TOK_INT
			{ $$.val = $1; $$.mask = 0xffffffff; }
	|	TOK_IP
	;

rangeopt:
		range
			{ $$ = $1; }
	|	':' integer
			{ $$.offset = 0; $$.len = $2; }
	|	integer ':'
			{ $$.offset = $1; $$.len = UINT_MAX; }
	;

range:
		integer
			{ $$.offset = $1; $$.len = 1; }
	|	integer ':' integer
			{ $$.offset = $1; $$.len = $3; }
	;

ipoption_list:
		ipoption_list ',' TOK_IP_OPTION_SYM
			{ $$ = $1 | $3; }
	|	TOK_IP_OPTION_SYM
			{ $$ = $1; }
	;

tcpstate_list:
		tcpstate_list ',' TOK_TCP_STATE_SYM
			{ $$ = $1 | $3; }
	|	TOK_TCP_STATE_SYM
			{ $$ = $1; }
	;

integer:
		TOK_INT
			{ $$ = $1; }
	|	TOK_IDENT
			{ $$ = id_to_uint($1); }
	;

string:
		TOK_STRING
			{ $$ = $1; }
	|	TOK_IDENT
			{ $$ = id_to_str($1); }
	;

pattern:
		TOK_PATTERN
			{ $$ = $1; }
	|	TOK_IDENT
			{ $$ = id_to_str($1); }
	;

%%

void rules_error(const char* msg)
	{
	fprintf(stderr, "Error in signature (%s:%d): %s\n",
			current_rule_file, rules_line_number+1, msg);
	rule_matcher->SetParseError();
	}

void rules_error(const char* msg, const char* addl)
	{
	fprintf(stderr, "Error in signature (%s:%d): %s (%s)\n",
			current_rule_file, rules_line_number+1, msg, addl);
	rule_matcher->SetParseError();
	}

void rules_error(Rule* r, const char* msg)
	{
	const Location& l = r->GetLocation();
	fprintf(stderr, "Error in signature %s (%s:%d): %s\n",
			r->ID(), l.filename, l.first_line, msg);
	rule_matcher->SetParseError();
	}

int rules_wrap(void)
	{
	return 1;
	}
