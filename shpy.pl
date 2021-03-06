#!/usr/bin/perl -w
#Written by Constantinos Paraskevopoulos in September 2015
#Converts simplistic and moderately complex Shell scripts into Python 2.7 scripts

$tab_count = "";
$commands = "ls|rm|touch|sleep|mkdir|rmdir|unzip|gzip";
$filters = "cat|wc|head|tail|sort|sed|grep|egrep|uniq|cut|paste";

#reads input shell source code from file(s) or from stdin
while ($line = <>) {
	#reformats current line
	chomp $line;
	$line =~ s/\s*$//;
	$line =~ s/^\s*//;
	$leading_whitespace = indent_code($line);
	$comment = "";

	#stores comment in variable and removes it from line to simplify pattern matching
	if ($line =~ /(\s+#.*)$/ && $line !~ /^#.*$/) {
		#second regex avoids matching start-of line comments
		$comment = $1;
		$line =~ s/$1$//;
	}

	if ($line =~ /^#!/ && $. == 1) {
		#converts hashbang line if present
		$interpreter = "#!/usr/bin/python2.7 -u";
	} else {
		#converts and appends all other lines to python code
		$line = parse_line($line);
		push @code, $leading_whitespace.$line;
	}

	#stores end-of-line comments in a hash aligned with current line of code
	if ($comment ne "") {
		$comments{$code[$#code]} = $comment;
	}

}

#copies end-of-line comments into python source code
$i = 0;
for ($i..$#code) {
	#appends comment to end of line
	$code[$i] .= $comments{$code[$i]} if $comments{$code[$i]};
	$i++;
}

#prints rendered python code to stdout
unshift @code, "#Converted by shpy.pl [".(scalar localtime)."]\n";
unshift @code, "$interpreter" if $interpreter;
foreach $line (@code) {
	print "$line\n" if $line !~ /^\s+$/;
}

#parses current line of shell script
sub parse_line {
	my $line = $_[0];
	if ($line =~ /^(#.*)/) {
		return "$1"; #copies start-of-line comments into python code
	} elsif ($line =~ /^echo -n ["'](\s*)["']$/) {
		#converts echo -n with blank string to sys.stdout.write("\s*")
		import("sys");
		return "sys.stdout.write(\"$1\")";
	} elsif ($line =~ /^echo -n$/) {
		#converts echo -n without args to sys.stdout.write("")
		import("sys");
		return "sys.stdout.write(\"\")";
	} elsif ($line =~ /^echo ["'](\s*)["']$/) {
		#converts echo with blank string to print with blank string
		return "print \"$1\"";
	} elsif ($line =~ /^echo$/) {
		#converts echo without args to print without args
		return "print";
	} elsif ($line =~ /^echo (-n )?(`|\$\()expr (.+)[`)]/) {
		#handles echo and echo -n with back quotes
		my ($print_newline, $shell_exp) = ($1, $3);
		$python_expression = convert_variable_initialisation($shell_exp);
		return "print $python_expression" if !$print_newline;
		import("sys");
		return "print $python_expression,\n".$leading_whitespace."sys.stdout.write('')";
	} elsif ($line =~ /^echo (-n )?\$\(\((.+)\)\)/) {
		#handles echo and echo -n with shell arithmetic
		my ($print_newline, $shell_exp) = ($1, $2);
		$python_expression = convert_variable_initialisation($shell_exp);
		return "print $python_expression" if !$print_newline;
		import("sys");
		return "print $python_expression,\n".$leading_whitespace."sys.stdout.write('')";
	} elsif ($line =~ /^echo -n (.+)/) {
		#converts all other calls to echo -n to calls to print
		return convert_echo($1, 0);
	} elsif ($line =~ /^echo (.+?)\s+>(>)?\s*(.+)/) {
		#matches shell i/o redirection
		my ($echo_to_print, $output_method, $file) = ($1, $2, $3);
		my $data = convert_echo($echo_to_print, 1);
		$data =~ s/^print //;
		$file = map_option_arg($file);
		$output_method = "w" if !$output_method;
		$output_method = "a" if $output_method;
		return "with open($file, '$output_method') as f: print >>f, $data";
	} elsif ($line =~ /^echo (.+)/) {
		#converts all other calls to echo to calls to print
		return convert_echo($1, 1);
	} elsif ($line =~ /^(echo `|echo \$\()?(chmod|cp|mv|join)[`)]?( -.+)* (.+) (.+)/) {
		#converts the unix commands chmod, cp, mv and join into system calls
		my ($cmd, $options, $arg1, $arg2) = ($2, $3, $4, $5);

		$options =~ s/ /', '/g if $options; #separates options
		$options =~ s/^', '// if $options; #removes empty leading option

		#handles the arguments "$*", $[@*], $[0-9]+ and $.+ separately
		my $first_arg = map_option_arg($arg1);
		my $second_arg = map_option_arg($arg2);

		#generates system call string
		if ($arg2 =~ /\$[\@\*]/) {
			$system_call = "['$cmd', '$options', $first_arg] + $second_arg" if $options;
			$system_call = "['$cmd', $first_arg] + $second_arg" if !$options;
		} else {
			$system_call = "['$cmd', '$options', $first_arg, $second_arg]" if $options;
			$system_call = "['$cmd', $first_arg, $second_arg]" if !$options;
		}

		import("subprocess");
		return "subprocess.call($system_call)";
	} elsif ($line =~ /^(echo `|echo \$\()?($commands|$filters)[`)]?( -.+)* (.+)/) {
		#converts various other unix commands and filters into system calls
		my ($cmd, $options, $args) = ($2, $3, $4);
		$options =~ s/ /', '/g if $options; #separates options
		$options =~ s/^', '// if $options; #removes empty leading option

		#handles the arguments "$*", $[@*], $[0-9]+ and $.+ separately
		my $arg = map_option_arg($args);

		#generates system call string
		if ($args =~ /\$[\@\*]/) {
			$system_call = "['$cmd', '$options'] + $arg" if $options;
			$system_call = "['$cmd'] + $arg" if !$options;
		} else {
			$system_call = "['$cmd', '$options', $arg]" if $options;
			$system_call = "['$cmd', $arg]" if !$options;
		}

		import("subprocess");
		return "subprocess.call($system_call)";
	} elsif ($line =~ /^(echo `|echo \$\()?(ls|pwd|id|date)[`)]?( -.+)*/) {
		#converts the unix commands ls, pwd, id and date into system calls
		my ($cmd, $options) = ($2, $3);
		$options =~ s/ /', '/g if $options; #separates options
		$options =~ s/^', '// if $options; #removes empty leading option
		$system_call = "['$cmd', '$options']" if $options;
		$system_call = "['$cmd']" if !$options;
		import("subprocess");
		return "subprocess.call($system_call)";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=(`|\$\()expr (.+)[`)]/) {
		#handles variable initialisation involving 'var=`expr .+`' or 'var=$(expr .+)'
		my ($variable, $shell_expression) = ($1, $3);
		$python_expression = convert_variable_initialisation($shell_expression);
		return "$variable = $python_expression";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=\$\(\((.+)\)\)/) {
		#handles variable initialisation involving 'var=$((.+))'
		my ($variable, $shell_expression) = ($1, $2);
		$python_expression = convert_variable_initialisation($shell_expression);
		return "$variable = $python_expression";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=\$#/) {
		#handles variable initialisation involving 'var=$#'
		import("sys");
		return "$1 = len(sys.argv) - 1";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=\$([0-9]+)/) {
		#handles variable initialisation involving 'var=$[0-9]+'
		import("sys");
		return "$1 = sys.argv[$2]";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=\$([^ ]+)/) {
		#handles variable initialisation involving 'var=$.+'
		return "$1 = $2";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=([0-9]+)/) {
		#handles variable initialisation involving 'var=num'
		return "$1 = $2";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=\"(.+)\"/) {
		#handles variable initialisation involving 'var="val"'
		my ($name, $value) = ($1, $2);
		$value = map_option_arg($value);
		return "$name = $value";
	} elsif ($line =~ /^([a-zA-Z_][a-zA-Z0-9_]*)=(.+)/) {
		#handles variable initialisation involving 'var=val'
		my ($name, $value) = ($1, $2);
		$value =~ s/\"(.*)\"/$1/; #removes leading/trailing "
		$value =~ s/'(.*)'/$1/; #removes leading/trailing '
		return "$name = '$value'";
	} elsif ($line =~ /^cd ([^ ]+)/) {
		import("os");
		return "os.chdir('$1')";
	} elsif ($line =~ /^exit ([0-9]+)/) {
		import("sys");
		return "sys.exit($1)";
	} elsif ($line =~ /^read ([^ ]+)/) {
		import("sys");
		return "$1 = sys.stdin.readline().rstrip()";
	} elsif ($line =~ /^for ([^ ]+) in \"\$\*\"$/) {
		#handles for loops involving "$*"
		my $loop_variable = $1;
		import("sys");
		$tab_count =~ s/\t//; #decrements tab count
		return "$loop_variable = ' '.join(sys.argv[1:])";
	} elsif ($line =~ /^for ([^ ]+) in \"?\$[\@\*]/) {
		#handles for loops involving $[@*] or "$@"
		import("sys");
		return "for $1 in sys.argv[1:]:";
	} elsif ($line =~ /^for ([^ ]+) in ([^\?\*]+)/) {
		#handles for loops which iterate over a list
		return map_for_loops($1, $2);
	} elsif ($line =~ /^for ([^ ]+) in (.+)/) {
		#handles for loops which iterate over files
		my ($loop_variable, $file_type) = ($1, $2);
		import("glob");
		return "for $loop_variable in sorted(glob.glob(\"$file_type\")):";
	} elsif ($line =~ /^while read ([^ ])/) {
		#converts loops which obtain user input
		import("sys");
		return "for $1 in sys.stdin:";
	} elsif ($line =~ /^(if|elif|while) (! )?(true|false)/) {
		#handles if/elif/while with true/false
		my ($control, $negation, $cmd) = ($1, $2, $3);
		import("subprocess");
		return "$control not subprocess.call(['$cmd']):" if !$negation;
		return "$control subprocess.call(['$cmd']):" if $negation;
	} elsif ($line =~ /^(if|elif|while) (! )?(diff|cmp|fgrep)( -.+)* (.+) (.+)/) {
		#handles if/elif/while with diff/cmp/fgrep
		my ($control, $negation, $cmd, $options, $file1, $file2) = ($1, $2, $3, $4, $5, $6);
		$file1 = map_option_arg($file1);
		$file2 = map_option_arg($file2);
		$options =~ s/ /', '/g if $options; #separates options
		$options =~ s/^', '// if $options; #removes empty leading option
		$system_call = "['$cmd', '$options', $file1, $file2]" if $options;
		$system_call = "['$cmd', $file1, $file2]" if !$options;
		import("subprocess");
		return "$control not subprocess.call($system_call):" if !$negation;
		return "$control subprocess.call($system_call):" if $negation;
	} elsif ($line =~ /^(if|elif|while) (! )?test (.+)/) {
		#handles all other if/elif/while statements with test command
		my ($control, $negation, $expression) = ($1, $2, $3);
		my $python_expression = map_if_while($expression);
		$python_expression =~ s/ $//; #removes trailing space
		return "$control $python_expression:" if !$negation;
		return "$control not ($python_expression):" if $negation;
	} elsif ($line =~ /^(if|elif|while) (! )?\[(.+)\]/) {
		#handles all other if/elif/while statements with [ ] notation
		my ($control, $negation, $expression) = ($1, $2, $3);
		my $python_expression = map_if_while($expression);
		$python_expression =~ s/ $//; #removes trailing space
		return "$control $python_expression:" if !$negation;
		return "$control not ($python_expression):" if $negation;
	} elsif ($line =~ /^:/) {
		return "pass"; #matches empty statements
	} elsif ($line =~ /^(break|continue)/) {
		return "$1"; #matches break, continue
	} elsif ($line =~ /^else/) {
		return "else:"; #translates 'else' into 'else:'
	} elsif ($line =~ /^(do|done|then|fi)/) {
		return " "; #appends blank line for correct alignment of comments
	} elsif ($line =~ /^$/) {
		return ""; #transfers blank lines for correct alignment of comments
	} else {
		return "#$line [UNTRANSLATED CODE]"; #converts all other lines into untranslated comments
	}
}

#prepends an import of the given package to the code if not already present
sub import {
	my $package = $_[0];
	unshift @code, "import $package" if !grep(/^import $package$/, @code);
}

#re-indents a given line of code based on the previous tab count
sub indent_code {
	my $line = $_[0];
	my $indentation = $tab_count; #copies current tab count
	if ($line =~ /^(if|while|for)/) {
		$tab_count .= "\t"; #increments for next line/block
	} elsif ($line =~ /^(elif|else)/) {
		$tab_count =~ s/\t//; #decrements tab count temporarily
		$indentation = "$tab_count"; #copies decremented tab count
		$tab_count .= "\t"; #re-increments for next line/block
	} elsif ($line =~ /^(fi|done)/) {
		$tab_count =~ s/\t//; #decrements tab count at end of control structure
	}
	return $indentation;
}

#converts numeric and non-numeric test operators to python style operators
sub convert_operator {
	my $operator = $_[0];
	if ($operator eq "eq" || $operator =~ /^=/) {
		return "=="; #accounts for -eq, = and ==
	} elsif ($operator eq "ne" || $operator eq "!=") {
		return "!=";
	} elsif ($operator eq "lt" || $operator =~ /</) {
		return "<"; #accounts for -lt, \<, '<' and "<"
	} elsif ($operator eq "le") { 
		return "<=";
	} elsif ($operator eq "gt" || $operator =~ />/) {
		return ">"; #accounts for -gt, \>, '>' and ">"
	} elsif ($operator eq "ge") {
		return ">=";
	}
}

#converts variable initialisations involving var=`expr .+`, var=$(expr .+) and var=$((.+))
sub convert_variable_initialisation {
	my $shell_exp = $_[0];
	$shell_exp =~ s/\s+/ /g; #condenses whitespace to increase readability
	my @shell_exp = split / /, $shell_exp;
	my $python_exp = "";

	#converts each expression from shell style to python style
	foreach $expression (@shell_exp) {
		$expression =~ s/\\(.+)/$1/; #converts operators escaped with \
		$expression =~ s/\"(.+)\"/$1/; #converts operators escaped with ""
		$expression =~ s/'(.+)'/$1/; #converts operators escaped with ''
		$python_exp .= "(" if $expression =~ /^\(/; #appends open bracket
		if ($expression =~ /\$([0-9]+)/) {
			$python_exp .= "int(sys.argv[$1]) "; #handles special vars
			import("sys");
		} elsif ($expression =~ /\$#/) {
			$python_exp .= "(len(sys.argv) - 1) "; #handles '$#' var
			import("sys");
		} elsif ($expression =~ /\$(.+)/) {
			$python_exp .= "int($1) "; #handles all other vars
		} else {
			#copies arithmetic operators and numeric values
			my $filtered_expression = $expression;
			$filtered_expression =~ s/[)(]//; #removes brackets
			$python_exp .= "$filtered_expression ";
		}
		$python_exp =~ s/\s+$// if $expression =~ /\)$/; #removes space before bracket
		$python_exp .= ") " if $expression =~ /\)$/; #appends close bracket
	}

	$python_exp =~ s/\( /\(/g; #increases readability by condensing spaces
	$python_exp =~ s/ $//; #removes trailing ' ' char
	return $python_exp;
}

#converts calls to echo to calls to print
sub convert_echo {
	my ($echo_to_print, $print_newline) = @_;

	#handles the case where entire string passed to echo is within single quotes
	if ($echo_to_print =~ /^'.*'$/) {
		$echo_to_print =~ s/'//g;
		if ($print_newline == 1) {
			return "print '$echo_to_print'";
		} elsif ($print_newline == 0) {
			import("sys");
			return "sys.stdout.write('$echo_to_print')";
		}
	}

	$interpolate_variables = 1 if $echo_to_print =~ /^\".*\"$/;
	$interpolate_variables = 0 if $echo_to_print !~ /^\".*\"$/;
	$echo_to_print =~ s/"//g; #removes all occurrences of double quotes from string
	my @words = split / /, $echo_to_print;
	$string_to_print = "";
	my $i = 0;

	#handles each 'word' on echo line
	while ($i <= $#words) {

		#removes $ from variables and formats words as <var> or '<var>'
		if ($words[$i] =~ /\$/) {
			append_variables($words[$i]);
		} else {
			$string_to_print .= "\"$words[$i]\", " if $words[$i];
		}

		$i++;
	}

	#returns appropriate print string according to whether newline requires printing
	if ($print_newline) {
		$string_to_print =~ s/, $//; #removes trailing ', '
		return "print $string_to_print";
	} else {
		import("sys");
		return "print $string_to_print\n".$leading_whitespace."sys.stdout.write('')" if $string_to_print;
		return "sys.stdout.write('')";
	}
}

#appends variables and adjacent chars/single quotes to string to be printed
sub append_variables {
	my ($word, $match) = @_;
	my @words = split /\$/, $word;

	#deals with the case of the variable being '$var1[$varn]*'
	if ($word =~ /^'+(.+)'+$/ && $interpolate_variables == 0) {
		$string_to_print .= "\"$1\", ";
		return;
	}

	$words[0] =~ s/'//g if $interpolate_variables == 0;
	$string_to_print .= "\"$words[0]\" + " if $word =~ /^([^\$]+)\$/; #appends leading chars

	#deals with variables of the form $var1[$varn]*
	my $i = 1;
	while ($i <= $#words) {
		#filters out empty strings
		$i++ if $words[$i] =~ /^$/;
		last if $i > $#words;

		$words[$i] =~ s/'//g; #deals with ' chars later
		my $mapped_variable = map_special_variable($words[$i]);

		#handles variables of the form $var[trailing chars]+
		if ($words[$i] =~ /^([a-zA-Z_][a-zA-Z0-9_]*|[@*#]|[0-9]+)([^a-zA-Z0-9_']+)$/) {
			my $trailing_chars = $2;
			$mapped_variable =~ s/$trailing_chars$//;
			$string_to_print .= "$mapped_variable + '$trailing_chars'";
		} else {
			$string_to_print .= "$mapped_variable";
		}

		#appends appropriate connector
		$string_to_print .= " + " if $i < $#words;
		$string_to_print .= ", " if $i == $#words && $word !~ /('+)$/;
		$string_to_print .= " + " if $i == $#words && $word =~ /('+)$/ && $interpolate_variables == 1;
		$string_to_print .= ", " if $i == $#words && $word =~ /('+)$/ && $interpolate_variables == 0;

		$i++;
	}

	#appends trailing '+ whenever entire string is double quoted
	$string_to_print .= "\"$1\", " if $word =~ /('+)$/ && $interpolate_variables == 1;
}

#maps shell metavariables to their python analogues
sub map_special_variable {
	my $var = $_[0];

	#handles ordinary variables
	if ($var =~ /[a-zA-Z_][a-zA-Z0-9_]*/) {
		return $var;
	}

	#handles special variables
	import("sys");
	if ($var =~ /^([0-9]+)/) {
		return "sys.argv[$1]";
	} elsif ($var =~ /^\@/) {
		return "sys.argv[1:]";
	} elsif ($var =~ /^\*/ && $interpolate_variables == 0) {
		return "sys.argv[1:]";
	} elsif ($var =~ /^\*/ && $interpolate_variables == 1) {
		return "' '.join(sys.argv[1:])";
	} elsif ($var =~ /^\#/) {
		return "(len(sys.argv) - 1)";
	}

}

#maps options or arguments to their interpolated values
sub map_option_arg {
	my $input = $_[0];

	if ($input =~ /^\"\$(.+)\"/) {
		#interpolates variables with double quotes
		$interpolate_variables = 1;
		$input = map_special_variable($1);
	} elsif ($input =~ /^('.+')$/) {
		#returns args and variables within single quotes
		$input = $1;
	} elsif ($input =~ /^\$/) {
		#interpolates other variables
		$input =~ s/^\$//;
		$interpolate_variables = 0;
		$input = map_special_variable($input);

		#non-special variables require str(var)
		$input = "str($input)" if $_[0] =~ /\$[a-zA-Z_][a-zA-Z0-9_]*/;
	} elsif ($input =~ /^\".+\"$/) {
		return $input; #returns original string
	} else {
		$input = "'$input'"; #returns quoted string
	}
	return $input;
}

#maps a shell file test to its python analogue
sub map_file_test {
	my ($test_operator, $file) = @_;
	import("os");
	$file = map_option_arg($file); #interprets variables first

	#determines python command based on test operator
	if ($test_operator eq "-e") {
		return "os.path.exists($file)";
	} elsif ($test_operator =~ /([rwx])/) {
		my $rwx = $1;
		$rwx =~ tr/rwx/RWX/;
		return "os.access($file, os.$rwx"."_OK)";
	} elsif ($test_operator eq "-f") {
		return "os.path.isfile($file)"
	} elsif ($test_operator eq "-d") {
		return "os.path.isdir($file)";
	} elsif ($test_operator eq "-h" || $test_operator eq "-L") {
		return "os.path.islink($file)";
	}

}

#maps all if/elif and while statements to their python analogues
sub map_if_while {
	my $expression = $_[0];
	my @terms = $expression =~ /(".+?"|'.+?'|\S+)/g; #splits string at spaces and quotes
	my $python_expression = "";
	my $i = 0;

	#maps each term of the shell expression to its analogue in python
	while ($i <= $#terms) {
		#skips empty terms and [ or ] terms
		while ($terms[$i] =~ /^\s*$/ || $terms[$i] =~ /^[][]$/) {
			$i++;
			last if $i > $#terms;
		}

		if ($terms[$i] eq "-a" || $terms[$i] eq "&&") {
			$python_expression .= "and";
		} elsif ($terms[$i] eq "-o" || $terms[$i] eq "||") {
			$python_expression .= "or";
		} elsif ($terms[$i] eq "!") {
			$python_expression .= "not";
		} elsif ($terms[$i] =~ /^-(eq|ne|lt|le|gt|ge)$/) {
			#matches numeric comparisons
			$python_expression .= convert_operator($1);
		} elsif ($terms[$i] =~ /[<=>]/) {
			#matches string comparisons
			$python_expression .= convert_operator($terms[$i]);
		} elsif ($terms[$i] =~ /^-[erwxfdhL]$/) {
			#matches file test operators
			$python_expression .= map_file_test($terms[$i], $terms[++$i]);
		} elsif ($terms[$i] =~ /^\$/) {

			#maps special variables to their python analogues
			if ($terms[$i - 1] && $terms[$i - 1] =~ /[<=>]/) {
				$python_expression .= map_option_arg($terms[$i]);
			} elsif ($terms[$i + 1] && $terms[$i + 1] =~ /[<=>]/) {
				$python_expression .= map_option_arg($terms[$i]);
			} else {
				$python_expression .= "int(";
				$python_expression .= map_option_arg($terms[$i]);
				$python_expression .= ")";
			}

		} elsif ($terms[$i - 1] && $terms[$i - 1] =~ /[<=>]/) {
			#maps strings
			if ($terms[$i] =~ /^\".*\"$/ || $terms[$i] =~ /^'.*'$/) {
				$python_expression .= "$terms[$i]";
			} else {
				$python_expression .= "'$terms[$i]'";
			}
		} elsif ($terms[$i + 1] && $terms[$i + 1] =~ /[<=>]/) {
			#maps strings
			if ($terms[$i] =~ /^\".*\"$/ || $terms[$i] =~ /^'.*'$/) {
				$python_expression .= "$terms[$i]";
			} else {
				$python_expression .= "'$terms[$i]'";
			}
		} else {
			#maps remaining terms as integers
			$python_expression .= "int($terms[$i])"
		}
		$python_expression .= " ";
		$i++;
	}

	return $python_expression;
}

#maps for loops to their python analogues
sub map_for_loops {
	my ($loop_variable, $args) = @_;
	my @args = $args =~ /(".+?"|'.+?'|\S+)/g; #splits string at spaces and quotes
	my $loop_args = "";
	my $i = 0;

	#appends each arg to loop in the appropriate format
	while ($i <= $#args) {
		#skips empty args
		while ($args[$i] =~ /^\s*$/) {
			$i++;
			last if $i > $#args;
		}

		$loop_args .= map_option_arg($args[$i]).", "; #handles variables
		$i++;
	}

	$loop_args =~ s/, $/:/; #converts last instance of ", " to :
	return "for $loop_variable in $loop_args";
}
