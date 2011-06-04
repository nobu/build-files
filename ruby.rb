#!/usr/bin/ruby

command = []
envs = {}
while arg = ARGV[0]
  break ARGV.shift if arg == '--'
  /\A--([-\w]+)(?:=(.*))?\z/ =~ arg or break
  arg, value = $1, $2
  re = Regexp.new('\A'+arg.gsub(/\w+\b/, '\&\\w*')+'\z', "i")
  case
  when re =~ "debug"
    debug = true
  when re =~ "srcdir"
    srcdir = value
  when re =~ "archdir"
    archdir = value
  when re =~ "cpu"
    command.concat(%w[arch -arch]) << value
  when re =~ "extout"
    extout = value
  when re =~ "precommand"
    require 'shellwords'
    command.concat(Shellwords.shellwords(value))
  when re =~ "gdb"
    command.unshift("gdb", "--args")
  when re =~ "rubyopt"
    rubyopt = value
  when re =~ "print-libraries"
    print_libraries = true
  when re =~ "version" && value
    unless File.directory?(dir = File.join(srcdir || File.dirname(__FILE__), value))
      abort "#{$0}: version #{value} not found"
    end
    version = value
    srcdir = dir
  when re =~ "env"
    value = value.split(/=/, 2)
    envs[value.first] = value.last
  else
    break
  end
  ARGV.shift
end

srcdir ||= File.dirname(__FILE__)
rbconf = "rbconfig.rb"
arch = ENV["arch"] || ENV["ARCH"] || RUBY_PLATFORM.sub(/^universal\./, '')
i386 = ("i3#{$1}" if /^i[4-9](86-.*)/ =~ arch)
universal = ("universal-darwin" if /darwin/ =~ arch)
begin
  abs_archdir = (File.expand_path(archdir, srcdir) if archdir)
  if abs_archdir and File.file?(conffile = File.join(abs_archdir, rbconf))
    config = File.read(conffile)
  elsif File.file?(conffile = File.join(abs_archdir = File.join(srcdir, arch), rbconf))
    config = File.read(conffile)
  elsif i386 and File.file?(conffile = File.join(abs_archdir = File.join(srcdir, i386), rbconf))
    config = File.read(conffile)
  elsif universal and File.file?(conffile = File.join(abs_archdir = File.join(srcdir, universal), rbconf))
    config = File.read(conffile)
  elsif File.file?(conffile = File.join(abs_archdir = File.join(srcdir, "."+arch), rbconf))
    config = File.read(conffile)
  elsif i386 and File.file?(conffile = File.join(abs_archdir = File.join(srcdir, "."+i386), rbconf))
    config = File.read(conffile)
  elsif universal and File.file?(conffile = File.join(abs_archdir = File.join(srcdir, "."+universal), rbconf))
    config = File.read(conffile)
  elsif !version
    srcdir = File.join(srcdir, version = "trunk")
    redo
  else
    abort "archdir not defined"
  end
end while false

config.sub!(/^(\s*)RUBY_VERSION\s*==.*(\sor\s*)$/, '\1true\2')
config = Module.new {
  module_eval(config, conffile)
  RbConfig = Config unless const_defined?(:RbConfig)
}::RbConfig::CONFIG

if /cygwin/ =~ RUBY_PLATFORM and /cygwin/ !~ config["target_os"]
  def File.extern_path(path)
    path = IO.popen("-") {|f| f || exec("realpath", path); f.read}.chomp
    IO.popen("-") {|f| f || exec("cygpath", "-ma", path); f.read}.chomp
  end
else
  class << File
    alias extern_path expand_path
  end
end

begin
  require 'pathname'
  abs_archdir = Pathname.new(abs_archdir).realpath.to_s
rescue Errno::EINVAL
  abs_archdir = File.extern_path(abs_archdir)
end

ruby = File.basename(__FILE__).sub(/ruby/, config['ruby_install_name'])
ruby = File.expand_path(ruby+config['EXEEXT'], abs_archdir)
File.exist?(ruby) or abort "#{ruby} is not found."

libs = [abs_archdir]
if extout
  abs_extout = File.extern_path(extout)
elsif extout = config["EXTOUT"]
  abs_extout = File.join(abs_archdir, extout)
end
if abs_extout
  if File.directory?(common = File.join(abs_extout, "common"))
    libs << common
  end
  libs << File.join(abs_extout, config["arch"])
end
if e = ENV["RUBYOPT"]
  dlext = "." + config["DLEXT"]
  e.scan(/(?:\A|\s)r(\S+)/) do |lib,|
    libs << lib if lib = $:.find do |d|
      d = File.join(d, lib)
      File.file?(d + ".rb") or File.file?(d + dlext)
    end
  end
end
if File.directory?(lib = File.expand_path("lib", srcdir)) or
    File.directory?(lib = File.expand_path("src/lib", srcdir))
  libs << lib
end

ENV["RUBY"] = File.extern_path(ruby)
ENV["PATH"] = [abs_archdir, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)
ENV["RUBYOPT"] = rubyopt if rubyopt

libs.collect!(&File.method(:extern_path))
libs.uniq!
if e = ENV["RUBYLIB"]
  libs << e
end
case config["arch"]
when /mswin|bccwin|mingw|msdosdjgpp|human|os2/
  pathsep = ";"
when /riscos/
  pathsep = ","
else
  pathsep = ":"
end
ENV["RUBYLIB"] = libs.join(pathsep)

libruby_so = File.join(abs_archdir, config['LIBRUBY_SO'])
if File.file?(libruby_so)
  if e = config['LIBPATHENV'] and !e.empty?
    ENV[e] = [abs_archdir, ENV[e]].compact.join(pathsep)
  end
  if /linux/ =~ RUBY_PLATFORM
    ENV["LD_PRELOAD"] = [libruby_so, ENV["LD_PRELOAD"]].compact.join(' ')
  end
end
ENV["DYLD_PRINT_LIBRARIES"] = "1" if print_libraries

ENV.update(envs)

command << ruby
exec *command.concat(ARGV)
