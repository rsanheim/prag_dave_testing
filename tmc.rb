# -*- encoding: utf-8 -*-
# This code is a proof-of-concept of a simple testing library.
# It comes with no warranty (and no tests) and is guaranteed to 
# be broken in more ways than a teenager's heart. Use at your own risk.
#
# This code is unsupported. Requests for changes, bug reports, 
# and patches will be silently but brutally ignored.
#
# Usage: see end of file
#
# Copyright (c) 2008, Dave Thomas <dave@pragprog.com> 
# All rights reserved.
# http://pragdave.pragprog.com
#
# LICENSE:
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the Dave Thomas nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY DAVE THOMAS “AS IS” AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL DAVE THOMAS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#


# WARNING--there's a major problem that folks building from this library
# will need to address. Ruby doesn't really have != and !~ methods. Instead,
# the parser maps (a != b) into !(a == b). This means that the ComparisonProxy
# cannot intercept calls to either of these. This is a problem because
#
#   expect(1) != 1
#
# actually passes, because it becomes !(expect(1) == 1), and the expect method
# is happy with that.
#
# I'm betting there's a way around this...   Dave
 

class TestResultsGatherer
  require 'singleton'
  include Singleton
  
  def initialize
    @failures = @successes = 0
    at_exit { report_test_statistics }
  end
  
  # Report a failure, giving context fromm the source file that caused it
  def report_failure(message)
    @failures += 1
    file, line = caller(3)[0].split(/:/, 2)
    line = line.to_i
    lines = File.readlines(file)
    line_in_error = lines[line-1]
    comment = find_comment(lines, line-1)

    STDERR.print "\n#{file}:#{line}"
    STDERR.print "—while testing #{@description}" if @description
    STDERR.puts
    STDERR.puts "\t#{comment}" if comment
    STDERR.puts "\tthe code was: #{line_in_error.strip},"
    STDERR.puts "\tbut #{message}"
  end
  
  def report_success
    @successes += 1
  end
  
  def report_test_statistics
    STDERR.puts "\n#{pluralize_test(@successes)} passed, #{pluralize_test(@failures)} failed"
  end
    

  private
  
  LINE_COMMENT = /^\s*#\s*/
    
  # Search back from a line for immediately preceding comments. Skip blank lines,
  # and then accept any consecutive comment lines. We also accept a trailing comment
  # on the line causing the error
  def find_comment(lines, line)
    return $1 if lines[line].sub!(/#\s*(.*)/, '')
      
    end_comment_line = line - 1
    while end_comment_line >= 0 && lines[end_comment_line] =~ /^\s*$/
      end_comment_line -= 1
    end

    return nil if end_comment_line < 0 || lines[end_comment_line] !~ LINE_COMMENT
    
    start_comment_line = end_comment_line
    while start_comment_line > 0 && lines[start_comment_line-1] =~ LINE_COMMENT
      start_comment_line -= 1
    end
    
    lines[start_comment_line..end_comment_line].map {|line| line.sub(LINE_COMMENT, '').strip}.join(" ")
  end

  def pluralize_test(count)
    count == 1 ? "1 test" : "#{count} tests"
  end
end




class ComparisonProxy
  # Comparison operators we support and their opposites
  OPERATORS = {}
  [
   [ :">" , :"<=" ],
   [ :">=", :"<"  ],
   [ :"==", :"!=" ],
   [ :"==", :"!=" ],
   [ :"==", :"!=" ]
  ].each {|op1, op2| OPERATORS[op1] = op2; OPERATORS[op2] = op1 }

  # Then ones that don't have opposites
  OPERATORS[:"==="] = "not ==="
  
  # the following two are here because the Ruby parser maps a != b and a !~ b 
  # to  !(a == b) and  !(a =~ b). Sigh...
  OPERATORS[:"=="]  = "!="
  OPERATORS[:"=~"]  = "!~"
  
  OPERATORS.keys.each do |comparison_op|
    define_method(comparison_op) do |other|
      __compare(comparison_op, other)
    end
  end
  
  def initialize(test_runner, value, description)
    @test_runner = test_runner
    @value       = value
    @description = description
  end
    
  private
  
  def __compare(op, other)
    if @value.send(op, other)
      @test_runner.report_success
    else
      @test_runner.report_failure("#{@value.inspect} #{OPERATORS[op]} #{other.inspect}")
    end
  end

end

def expect(value)
  ComparisonProxy.new(TestResultsGatherer.instance, value, @__test_description)
end

# Save any instance variables, yield to our block, then restore the instance
# variables. We also save the test description in @__test_description. This is
# tacky, but has the nice side effect of saving and restoring it in nested
# testing blocks
def testing(description)
  ivs = {}
  instance_variables.each do |iv|
    ivs[iv] = instance_variable_get(iv)
  end
  saved = Marshal.dump(ivs)
  @__test_description = description
  yield
  @__test_description = nil
  instance_variables.each { |iv| instance_variable_set(iv, nil) }
  ivs = Marshal.load(saved)
  ivs.each do |iv, value|
    instance_variable_set(iv, value)
  end
end

# Examples of all this in action...

if __FILE__ == $0

  # Regular tests
  expect(1) == 1
  expect(1) < 3
  expect("cat") =~ /[aeiou]/

  # groups of tests
  testing("negative numbers") do
    expect(-3) <= -3
    expect(-1) > -1000
    testing("negative floating point numbers") do
      expect(-3.0) <= -3
    end
  end

  # Transactional instance variables rather than setup()
  @var = "cat"
  expect(@var) =~ /a/
  testing("uppercase version") do
    @var.upcase!
    expect(@var) =~ /A/
    testing("reversed") do 
      @var = @var.reverse
      expect(@var) == "TAC"
    end
    expect(@var) == "CAT"
  end
  expect(@var) =~ /a/  # original value restored
  
  # this comment will annotate the following failed test
  expect(1) == 2
  
  expect(2) == 3  # so will this one

end
