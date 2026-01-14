#!/usr/bin/env python3

"""
File-Centric Sourcing Recommender
Analyzes each .sh file and recommends what it should source based on functions called
"""

import os
import re
import sys
import argparse
from pathlib import Path
from collections import defaultdict
from typing import Dict, Set, List, Any

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    BLUE = '\033[1;34m'
    GREEN = '\033[1;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[1;31m'
    CYAN = '\033[0;36m'
    GRAY = '\033[0;37m'
    MAGENTA = '\033[1;35m'

# Bash keywords and common builtins to ignore
BASH_KEYWORDS = {
    # Control structures
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done',
    'case', 'esac', 'select', 'function', 'time', 'coproc', 'in',
    # Variable/function declarations
    'local', 'readonly', 'declare', 'typeset', 'export', 'unset',
    # Flow control
    'return', 'exit', 'break', 'continue', 'shift',
    # I/O
    'echo', 'printf', 'read', 'test', 'true', 'false',
    # Directory operations
    'cd', 'pwd', 'pushd', 'popd', 'dirs',
    # Script operations
    'source', 'set', 'shopt', 'eval', 'exec', 'command', 'builtin',
    # Arithmetic and text processing
    'let', 'expr', 'bc', 'awk', 'sed', 'grep', 'find', 'xargs',
    # File operations
    'cat', 'head', 'tail', 'cut', 'sort', 'uniq', 'wc', 'tr',
    'mkdir', 'rm', 'cp', 'mv', 'ls', 'touch', 'chmod', 'chown',
    # Arrays
    'mapfile', 'readarray',
    # Other common commands
    'sleep', 'wait', 'kill', 'ps', 'basename', 'dirname',
}

# Files that are globally available (Layer 0 - sourced in bin/kdoitall)
GLOBALLY_SOURCED = {
    'lib/core/error-codes.sh',
    'lib/utils/debug.sh',
    'lib/core/common.sh',
    'lib/utils/checks.sh',
    'lib/utils/validators.sh',
    'lib/core/database.sh',
    'lib/db/window-tracking.sh',
    'lib/core/ydotool.sh',
    'lib/core/screen-detection.sh',
}

class SourcingAnalyzer:
    def __init__(self, lib_dir: Path, use_colors=True):
        self.lib_dir = lib_dir
        self.use_colors = use_colors
        self.function_map: Dict[str, str] = {}  # function_name -> relative_file_path
        self.file_functions: Dict[str, Set[str]] = defaultdict(set)  # file_path -> set of functions
        
    def cprint(self, color: str, text: str):
        """Print with color if enabled"""
        if self.use_colors:
            print(f"{color}{text}{Colors.RESET}")
        else:
            print(text)
    
    def get_relative_path(self, file_path: Path) -> str:
        """Get path relative to project root (lib directory's parent)"""
        try:
            project_root = self.lib_dir.parent
            return str(file_path.relative_to(project_root))
        except ValueError:
            return str(file_path)
    
    def extract_functions(self, file_path: Path) -> Set[str]:
        """Extract function definitions from a file"""
        functions = set()
        pattern = re.compile(r'^\s*(?:function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)\s*\{')
        
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    match = pattern.match(line)
                    if match:
                        func_name = match.group(1)
                        functions.add(func_name)
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
            
        return functions
    
    def is_in_heredoc_or_string(self, line: str, position: int) -> bool:
        """Check if position is inside a heredoc or string generation context"""
        # Simple heuristic: if line contains 'cat >>' or 'echo' before position
        # This catches cases like: echo "function_name" or cat >> file << EOF
        before_pos = line[:position].strip()
        
        # Check for heredoc patterns
        if '<<' in before_pos:
            return True
        
        # Check for echo/cat to file patterns
        if 'cat' in before_pos and ('>>' in before_pos or '>' in before_pos):
            return True
        if 'echo' in before_pos and ('>>' in before_pos or '>' in before_pos):
            return True
            
        return False
    
    def find_function_calls(self, file_path: Path, local_functions: Set[str]) -> Set[str]:
        """Find potential function calls in a file, excluding those in heredocs/strings"""
        potential_calls = set()
        # Match function-like patterns: word followed by space/parenthesis (including process substitution)
        # Matches: func(), func , <(func), $(func)
        pattern = re.compile(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:\(|\)|[\s])')
        
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                in_heredoc = False
                heredoc_marker = None
                
                for line in f:
                    stripped = line.strip()
                    
                    # Skip comments
                    if stripped.startswith('#'):
                        continue
                    
                    # Track heredoc state
                    if '<<' in line and not in_heredoc:
                        # Starting a heredoc
                        heredoc_match = re.search(r'<<\s*["\']?(\w+)["\']?', line)
                        if heredoc_match:
                            in_heredoc = True
                            heredoc_marker = heredoc_match.group(1)
                    elif in_heredoc and heredoc_marker and heredoc_marker in line:
                        # Ending a heredoc
                        in_heredoc = False
                        heredoc_marker = None
                        continue
                    
                    # Skip lines inside heredocs
                    if in_heredoc:
                        continue
                    
                    # Find potential function calls
                    for match in pattern.finditer(line):
                        word = match.group(1)
                        position = match.start()
                        
                        # Skip bash keywords
                        if word in BASH_KEYWORDS:
                            continue
                        
                        # Skip local functions
                        if word in local_functions:
                            continue
                        
                        # Skip if in string generation context
                        if self.is_in_heredoc_or_string(line, position):
                            continue
                        
                        potential_calls.add(word)
                        
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        
        return potential_calls
    
    def extract_current_sources(self, file_path: Path) -> Set[str]:
        """Extract current source statements from a file, normalized without lib/ prefix"""
        sources = set()
        # Match: source "${LIB_DIR}/path/file.sh"
        pattern = re.compile(r'source\s+["\$\{]*LIB_DIR[}\"]*/(.+\.sh)')
        
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    match = pattern.search(line)
                    if match:
                        # Normalize: always store without 'lib/' prefix
                        source_path = match.group(1)
                        sources.add(self.normalize_source_path(source_path))
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        
        return sources
    
    def normalize_source_path(self, source_path: str) -> str:
        """Normalize a source path for comparison"""
        # Remove 'lib/' prefix if present
        if source_path.startswith('lib/'):
            return source_path[4:]
        return source_path
    
    def build_function_map(self):
        """Build map of all functions to their source files"""
        self.cprint(Colors.BLUE, "Building function map...")
        
        shell_files = sorted(self.lib_dir.rglob("*.sh"))
        total_functions = 0
        
        for file_path in shell_files:
            functions = self.extract_functions(file_path)
            relative_path = self.get_relative_path(file_path)
            
            for func_name in functions:
                self.function_map[func_name] = relative_path
                self.file_functions[relative_path].add(func_name)
                total_functions += 1
        
        self.cprint(Colors.GREEN, f"✓ Mapped {total_functions} functions from {len(shell_files)} files")
        print()
    
    def analyze_file(self, file_path: Path) -> Dict:
        """Analyze a single file and return sourcing recommendations"""
        relative_path = self.get_relative_path(file_path)
        
        # Extract local functions (defined in this file)
        local_functions = self.file_functions.get(relative_path, set())
        
        # Extract called functions
        called_functions = self.find_function_calls(file_path, local_functions)
        
        # Extract current sources (normalized without lib/ prefix)
        already_sourced = self.extract_current_sources(file_path)
        
        # Calculate dependencies - group by source file
        dependencies_by_source: Dict[str, Dict[str, Any]] = {}
        used_sources = set()  # Track which sources are actually used
        
        for func_name in sorted(called_functions):
            # Skip if not in function map (unknown function)
            if func_name not in self.function_map:
                continue
            
            source_file = self.function_map[func_name]
            source_file_normalized = self.normalize_source_path(source_file)
            
            # Skip if this is the same file (local function we missed)
            if source_file == relative_path:
                continue
            
            # Track that this source file is used
            used_sources.add(source_file_normalized)
            
            # Determine status
            if source_file in GLOBALLY_SOURCED:
                status = "globally available"
            elif source_file_normalized in already_sourced:
                status = "already sourced"
            else:
                status = "MISSING"
            
            # Initialize entry if needed
            if source_file not in dependencies_by_source:
                dependencies_by_source[source_file] = {'functions': [], 'status': status}
            
            dependencies_by_source[source_file]['functions'].append(func_name)
            dependencies_by_source[source_file]['status'] = status
        
        # Check for unnecessary sources - sources that don't provide any used functions
        unnecessary_sources = []
        for sourced in already_sourced:
            full_path = f"lib/{sourced}"
            
            # Skip if it's globally sourced (those are okay to have)
            if full_path in GLOBALLY_SOURCED:
                continue
            
            # Check if this source is used
            if sourced not in used_sources:
                # Get functions from this source file
                functions_in_source = self.file_functions.get(full_path, set())
                unnecessary_sources.append({
                    'source': sourced,
                    'available_functions': sorted(functions_in_source) if functions_in_source else []
                })
        
        # Convert dependencies to list format
        dependencies = []
        for source_file in sorted(dependencies_by_source.keys()):
            info = dependencies_by_source[source_file]
            dependencies.append({
                'source': source_file,
                'status': info['status'],
                'functions': sorted(info['functions'])
            })
        
        return {
            'relative_path': relative_path,
            'already_sourced': sorted(already_sourced),
            'dependencies': dependencies,
            'unnecessary_sources': unnecessary_sources
        }
    
    def generate_report(self, verbose: bool = False):
        """Generate file-centric sourcing recommendations"""
        self.cprint(Colors.BLUE, "╔" + "═" * 58 + "╗")
        self.cprint(Colors.BLUE, "║" + " " * 10 + "File-Centric Sourcing Recommendations" + " " * 9 + "║")
        self.cprint(Colors.BLUE, "╚" + "═" * 58 + "╝")
        print()
        
        # Get all .sh files in lib/, excluding lib/app-definitions/
        shell_files = sorted([
            f for f in self.lib_dir.rglob("*.sh")
            #if not str(f).startswith(str(self.lib_dir / "app_definitions"))
        ])
        
        # Statistics tracking
        stats = {
            'total_files': 0,
            'files_with_missing': 0,
            'files_fully_sourced': 0,
            'files_no_deps': 0,
            'files_with_unnecessary': 0,
            'total_missing_deps': 0,
            'total_unnecessary': 0
        }
        
        # Group files by directory
        by_directory = defaultdict(list)
        for file_path in shell_files:
            directory = file_path.parent
            by_directory[directory].append(file_path)
        
        # Process each directory
        for directory in sorted(by_directory.keys()):
            dir_relative = self.get_relative_path(directory)
            files = by_directory[directory]
            
            self.cprint(Colors.CYAN, f"📁 {dir_relative}/")
            self.cprint(Colors.YELLOW, "━" * 60)
            print()
            
            for file_path in files:
                stats['total_files'] += 1
                analysis = self.analyze_file(file_path)
                
                # Track statistics
                has_missing = any(dep['status'] == 'MISSING' for dep in analysis['dependencies'])
                has_deps = len(analysis['dependencies']) > 0
                has_unnecessary = len(analysis['unnecessary_sources']) > 0
                
                if has_missing:
                    stats['files_with_missing'] += 1
                    missing_count = sum(1 for dep in analysis['dependencies'] if dep['status'] == 'MISSING')
                    stats['total_missing_deps'] += missing_count
                elif has_deps:
                    stats['files_fully_sourced'] += 1
                else:
                    stats['files_no_deps'] += 1
                
                if has_unnecessary:
                    stats['files_with_unnecessary'] += 1
                    stats['total_unnecessary'] += len(analysis['unnecessary_sources'])
                
                self.cprint(Colors.GREEN, f"📄 {analysis['relative_path']}")
                self.cprint(Colors.YELLOW, "─" * 60)
                
                # Show already sourced
                if analysis['already_sourced']:
                    print("✅ Already sources:")
                    for source in analysis['already_sourced']:
                        print(f"   • {source}")
                else:
                    print("✅ Already sources: (none)")
                
                # Show unnecessary sources
                if analysis['unnecessary_sources']:
                    self.cprint(Colors.MAGENTA, "⚠️  Unnecessary sources (not using any functions from):")
                    for unnecessary in analysis['unnecessary_sources']:
                        if verbose and unnecessary['available_functions']:
                            funcs = ', '.join(unnecessary['available_functions'])
                            func_info = f" (defines: {funcs})"
                        else:
                            func_info = ""
                        self.cprint(Colors.MAGENTA, f"   • {unnecessary['source']}{func_info}")
                
                # Show dependencies with status
                if analysis['dependencies']:
                    print("📊 Calls functions from:")
                    for dep in analysis['dependencies']:
                        status_marker = f"[{dep['status']}]"
                        if dep['status'] == "MISSING":
                            status_color = Colors.RED
                        elif dep['status'] == "globally available":
                            status_color = Colors.GRAY
                        else:
                            status_color = Colors.GREEN
                        
                        if verbose:
                            func_list = ', '.join(dep['functions'])
                            func_info = f" ({func_list})"
                        else:
                            func_info = ""
                        
                        if self.use_colors:
                            print(f"   • {dep['source']}{func_info} {status_color}{status_marker}{Colors.RESET}")
                        else:
                            print(f"   • {dep['source']}{func_info} {status_marker}")
                else:
                    print("✨ No function dependencies detected")
                
                print()
            
            self.cprint(Colors.YELLOW, "━" * 60)
            print()
        
        # Print summary
        print()
        self.cprint(Colors.BLUE, "╔" + "═" * 58 + "╗")
        self.cprint(Colors.BLUE, "║" + " " * 23 + "Summary" + " " * 28 + "║")
        self.cprint(Colors.BLUE, "╚" + "═" * 58 + "╝")
        print()
        print(f"Total files analyzed: {stats['total_files']}")
        print(f"Files with missing dependencies: {stats['files_with_missing']}")
        print(f"Files with unnecessary sources: {stats['files_with_unnecessary']}")
        print(f"Files fully sourced: {stats['files_fully_sourced']}")
        print(f"Files with no dependencies: {stats['files_no_deps']}")
        print(f"Total missing source statements needed: {stats['total_missing_deps']}")
        print(f"Total unnecessary source statements: {stats['total_unnecessary']}")
        print()


def main():
    parser = argparse.ArgumentParser(
        description='File-Centric Sourcing Recommender',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
  %(prog)s --verbose
  %(prog)s -o sourcing-report.txt
        """
    )
    
    parser.add_argument('--lib-dir', default='../lib',
                       help='Path to lib directory (default: ../lib)')
    parser.add_argument('-o', '--output', metavar='FILE',
                       help='Write output to file instead of stdout')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Show which specific functions triggered each dependency')
    parser.add_argument('--no-color', action='store_true',
                       help='Disable colored output')
    
    args = parser.parse_args()
    
    # Resolve paths
    script_dir = Path(__file__).parent.resolve()
    
    # Find lib directory
    lib_dir = Path(args.lib_dir)
    if not lib_dir.is_absolute():
        lib_dir = script_dir / lib_dir
    lib_dir = lib_dir.resolve()
    
    if not lib_dir.exists() or not lib_dir.is_dir():
        print(f"Error: Library directory not found: {lib_dir}", file=sys.stderr)
        sys.exit(1)
    
    # Disable colors if outputting to file or if requested
    use_colors = not args.output and not args.no_color
    
    # Redirect stdout if needed
    output_file = None
    if args.output:
        output_file = open(args.output, 'w')
        sys.stdout = output_file
    
    try:
        # Run analysis
        analyzer = SourcingAnalyzer(lib_dir, use_colors=use_colors)
        
        # Build function map
        analyzer.build_function_map()
        
        # Generate report
        analyzer.generate_report(verbose=args.verbose)
        
        if args.output:
            print(f"\nOutput written to: {args.output}", file=sys.stderr)
    
    finally:
        if output_file:
            output_file.close()
            sys.stdout = sys.__stdout__


if __name__ == '__main__':
    main()
