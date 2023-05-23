#!/usr/bin/ruby --disable=gems

command = []
envs = {}
dryrun = false
while arg = ARGV[0]
  break ARGV.shift if arg == '--'
  /\A--([-\w]+)(?:=(.*))?\z/ =~ arg or break
  arg, value = $1, $2
  re = Regexp.new('\A'+arg.gsub(/\w+\b/, '\&\\w*')+'\z', "i")
  case
  when re =~ "srcdir"
    srcdir = value
  when re =~ "archdir"
    archdir = value || (ARGV.shift && ARGV[0])
  when re =~ "cpu"
    command.concat(%w[arch -arch]) << value
  when re =~ "extout"
    extout = value
  when re =~ "precommand"
    require 'shellwords'
    command.concat(Shellwords.shellwords(value))
  when re =~ "gdb"
    command.unshift("--args")
    if value
      require 'shellwords'
      command.unshift(*Shellwords.shellwords(value))
    else
      command.unshift("gdb", "-q")
    end
  when re =~ "lldb"
    command.unshift("--")
    if value
      require 'shellwords'
      command.unshift(*Shellwords.shellwords(value))
    else
      lldbinit = File.join(File.dirname($0), "misc/lldb_cruby.py")
      lldbinit = "command script import -r #{lldbinit}"
      lldbinit = "breakpoint set -n ruby_sysinit -C #{lldbinit.dump} -C continue"
      command.unshift("lldb", "-o", lldbinit)
    end
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
    value = value.split(/\=/, 2)
    envs[value.first] = value.last
  when re =~ "dryrun"
    dryrun = true
  else
    break
  end
  ARGV.shift
end

srcdir ||= File.dirname(__FILE__)
rbconf = "rbconfig.rb"
archdir ||= (ARGV.shift if ARGV[0] && File.exist?(File.join(ARGV[0], rbconf)))
arch =
  if host = ENV["HOSTTYPE"] and os = ENV["OSTYPE"]
    "#{host}-#{os.sub(/(?:[.\d]+|-gnu)\z/, '')}"
  else
    ENV["PLATFORM"] || ENV["arch"] || ENV["ARCH"] || RUBY_PLATFORM.sub(/^universal\./, '')
  end
i386 = ("i3#{$1}" if /^i[4-9](86-.*)/ =~ arch)
universal = ("universal-darwin" if /darwin/ =~ arch)
archs = [arch, i386, universal].compact
if archdir and File.file?(conffile = File.join((abs_archdir = File.expand_path(archdir, srcdir)), rbconf))
  config = File.read(conffile)
else
  begin
    ["", ".+", ".", "../build/"].product(archs) do |pre, a|
      arch = pre+a
      if File.file?(conffile = File.join(abs_archdir = File.join(srcdir, arch), rbconf))
        config = File.read(conffile)
        break
      end
    end
    break if config
    if !version
      srcdir = File.join(srcdir, version = "trunk")
      redo
    else
      abort "archdir not defined"
    end
  end while false
end

config.sub!(/^(\s*)RUBY_VERSION\b.*(\sor\s*)$/, '\1true\2')
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
  abs_archdir = File.realpath(abs_archdir)
rescue Errno::EINVAL
  abs_archdir = File.extern_path(abs_archdir)
end

ruby = ENV["RUBY"]
begin
  break if ruby and File.exist?(ruby)
  name = File.basename($0, ".rb")
  if /\Amini/ =~ name
    ruby = File.expand_path(name+config['EXEEXT'], abs_archdir)
    break if File.exist?(ruby)
  end
  ruby = File.expand_path("exe/#$0"+config['EXEEXT'], abs_archdir)
  break if File.exist?(ruby)
  ruby = File.expand_path("ruby-runner"+config['EXEEXT'], abs_archdir)
  break if File.exist?(ruby)
  ruby = File.basename(__FILE__).sub(/ruby/, config['ruby_install_name'])
  ruby = File.expand_path(ruby+config['EXEEXT'], abs_archdir)
  break if File.exist?(ruby)
end while abort("#{ruby} is not found.")

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

envs["RUBY"] = File.extern_path(ruby)
envs["PATH"] = [abs_archdir, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)
envs["RUBYOPT"] = rubyopt if rubyopt

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
envs["RUBYLIB"] = libs.join(pathsep)

libruby_so = File.join(abs_archdir, config['LIBRUBY_SO'])
if File.file?(libruby_so)
  if e = config['LIBPATHENV'] and !e.empty?
    envs[e] = [abs_archdir, ENV[e]].compact.join(pathsep)
  end
  if /linux/ =~ RUBY_PLATFORM
    envs["LD_PRELOAD"] = [libruby_so, ENV["LD_PRELOAD"]].compact.join(' ')
  end
end
envs["DYLD_PRINT_LIBRARIES"] = "1" if print_libraries

gems = [abs_archdir + "/.bundle", File.expand_path(".bundle", srcdir)]
if gems.any? {|dir| File.directory?(dir)}
  if gem_path = ENV["GEM_PATH"]
    gems << gem_path
  end
  envs["GEM_PATH"] = gems.compact.join(pathsep)
end

ENV.update(envs)

command << ruby
command.concat(ARGV)
command.push(:close_others => false)
if dryrun
  envs.each do |k, v|
    puts "#{k}=#{v} \\"
  end
  puts command.join(" \\\n")
  exit
end
exec(*command)
