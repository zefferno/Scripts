#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import sys
import re

__author__ = 'Mor Kalfon'
__version__ = '1.0'
__email__ = 'zefferno@gmail.com'
__license__ = 'Apache'
__program_name__ = 're_search'
__description__ = "Search for Regular Expression pattern in one or more files"

"""
This script searches for one or more named input files or lines containing 
a match to a regular expression pattern (given on command line as well).
"""

class MatchOutputFormat(object):
    """ Prototype for match output format """

    def __init__(self, filename, line_no, line, matches):
        """
        Initialize MatchOutputFormat
        
        Arguments:
            filename: (str) File name of the match
            line_no: (int) Line number
            line: (str) Line text
            matches: (list) List of tuples that contain start, end positions for text matches
        """
        self.filename = filename
        self.line_no = line_no
        self.line = line
        self.matches = matches

    def __str__(self):
        pass


class StandardOutputFormat(MatchOutputFormat):
    """Compute string representation of Standard Output Format"""

    def __str__(self):
        if self.matches:
            return '[ Filename: {}, Line: {} ]\n{}'.format(self.filename, self.line_no, self.line)
        return ''


class MachineOutputFormat(MatchOutputFormat):
    """Compute string representation of Machine Output Format"""

    def __str__(self):
        out = ''

        # Format match result for each match
        for match in self.matches:
            out += '{}:{}:{}:{}\n'.format(self.filename,
                                          self.line_no,
                                          match[0],
                                          self.line[match[0]:match[1]])
        return out


class UnderscoreOutputFormat(MatchOutputFormat):
    """Compute string representation of Underscore Output Format"""

    def __str__(self):
        if not self.matches:
            return ''

        # Build terminal line in list representation
        temp = [' '] * len(self.line)

        # Add underscore for matched objects
        for match in self.matches:
            for i in range(match[0], match[1]):
                temp[i] = '^'

        return '[ Filename: {}, Line: {} ]\n{}'.format(self.filename, self.line_no, self.line) + ''.join(temp) + '\n'


class ColorOutputFormat(MatchOutputFormat):
    """Compute string representation of Color Output Format"""

    @staticmethod
    def __get_term_color(color):
        """
        Get ansi terminal color code
        
        Arguments:
            color: (str) Color name
        
        Returns:
            Terminal color code
        """
        color = color.lower().strip()

        if color == 'yellow':
            return '\033[1;33m'
        elif color == 'none':
            return '\033[0;0m'

    def __str__(self):
        out = ''
        anchor = 0

        if not self.matches:
            return out

        # Matched text in color
        for match in self.matches:
            out += self.line[anchor:match[0]]
            out += self.__get_term_color('yellow') + self.line[match[0]:match[1]] + self.__get_term_color('none')
            anchor = match[1]

        # Append the rest of the string
        out += self.line[self.matches[-1][1]:]

        return '[ Filename: {}, Line: {} ]\n{}'.format(self.filename, self.line_no, out)


def args_parser():
    """
    Handle program arguments

    Returns:
        Parsed arguments
    """
    parser = argparse.ArgumentParser(prog=__program_name__, description=__description__)
    parser.add_argument('pattern', type=str, help='Regular Expression pattern')
    parser.add_argument('file', nargs='*', type=argparse.FileType('r'), default=sys.stdin,
                        help='one or more input files, if not specified, stdin is used as input')

    group = parser.add_mutually_exclusive_group()
    group.add_argument('-u', '--underscore', action='store_true',help='prints "^" under the matching text')
    group.add_argument('-c', '--color', action='store_true', help='highlights matching text')
    group.add_argument('-m', '--machine', action='store_true', help='generate machine readable output: '
                                                                    'file_name:no_line:start_pos:matched_text')

    return parser.parse_args()


def main():
    args = args_parser()

    try:
        re_match = re.compile(args.pattern)
    except:
        print("ERROR: Check your RexEx input!")
    else:
        for f in args.file:
            screen_output = ''

            for line_no, line in enumerate(f):
                match_list = list()
                line_no += 1

                for match in re_match.finditer(line):
                    match_list.append(match.span())

                if args.color:
                    screen_output += str(ColorOutputFormat(f.name, line_no, line, match_list))
                elif args.underscore:
                    screen_output += str(UnderscoreOutputFormat(f.name, line_no, line, match_list))
                elif args.machine:
                    screen_output += str(MachineOutputFormat(f.name, line_no, line, match_list))
                else:
                    screen_output += str(StandardOutputFormat(f.name, line_no, line, match_list))

                del match_list

            if screen_output:
                print(screen_output)


if __name__ == "__main__":
    main()
