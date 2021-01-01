#!/usr/bin/ruby

require "ostruct"
require "optparse"
require "shellwords"
require_relative "./config.rb"



def error(fmt, *args)
  str = (if args.empty? then fmt else sprintf(fmt, *args) end)
  $stderr.printf("ERROR: %s\n", str)
  exit(1)
end

class QEMULauncher
  def self.available_architectures
    Dir.entries(Config::QEMU_HOME).each do |ent|
      path = File.join(Config::QEMU_HOME, ent)
      next unless File.file?(path)
      next unless ent.match(/^qemu-system-/)
      aname = ent.gsub(/^qemu-system-/i, "").gsub(/\.exe$/i, "")
      yield [aname, path]
    end
  end

  def initialize
    @arch = nil
    @archpath = nil
    @cmd = []
  end

  def setarch(arch)
    @arch = arch
    exe = sprintf("qemu-system-%s.exe", @arch)
    path = File.join(Config::QEMU_HOME, exe)
    if not File.file?(path) then
      error("arch %p unavailable; no executable named %p (%p)", @arch, exe, path)
    end
    @archpath = path
  end

  def get
    return @cmd
  end

  def set(flag, *args)
    @cmd.push(flag, *args)
  end

  def setmem(sz, szspec='M')
    set("-m", sprintf("%d%s", sz, szspec.upcase))
  end

  def launch
    if @arch == nil then
      error("no architecture specified via #setarch()")
    end
    realcmd = [@archpath, *@cmd]
    $stderr.printf("cmd: %s\n", realcmd.shelljoin)
    #exit
    exec(*realcmd)
  end
end

class QVMProgram
  def initialize(opts, argv)
    @opts = opts
    @qemu = QEMULauncher.new
    @qemu.set("-net", Config::DEFAULT_NET[0])
    @qemu.set("-net", Config::DEFAULT_NET[1])
    @opts.to_h.each do |key, val|
      if val != nil then
        case key
          when :keyboardlayout then
            @qemu.set("-k", val)
          when :arch then
            @qemu.setarch(val)
          when :ramsize then
            @qemu.setmem(val)
          when :cdrom then
            val.each do |sv|
              @qemu.set("-cdrom", sv)
            end
          when :harddisk then
            val.each do |sv|
              @qemu.set("-hda", sv)
            end
          else
            $stderr.printf("warning: unhandled option %p (value: %p)\n", key, val)
        end
      end
    end
    if not argv.empty? then
      if argv.length == 1 then
        @qemu.set(argv.first)
      else
        $stderr.printf("too many variadic arguments\n")
      end
    end
  end

  def launch
    @qemu.launch
  end
end

begin
  opts = OpenStruct.new({
    arch: Config::DEFAULT_ARCHITECTURE,
    ramsize: Config::DEFAULT_MEMSIZE,
    cdrom: [],
    harddisk: [],
    keyboardlayout: Config::DEFAULT_LANG,
  })
  ostr = proc{|n, str|
    fmt = sprintf("%s (default: %p)", str, opts[n])
  }
  (prs=OptionParser.new{|prs|
      prs.on("-h", "--help", "show this help and exit"){|_|
        print(prs.help)
        exit(0)
      }
      prs.on("-a<arch>", "--arch=<arch>", "--architecture=<arch>", ostr[:arch, "set architecture to use - use 'list' to see available"]){|v|
        if v == "list" then
          $stdout.printf("available architectures:\n")
          QEMULauncher.available_architectures do |arch, exe|
            $stdout.printf("  %p -> %p\n", arch, exe)
          end
          exit
        else
          opts.arch = v
        end
      }
      prs.on("-m<size>", "--memory=<size>", "--ram=<size>", ostr[:ramsize, "set RAM size"]){|v|
        opts.ramsize = v.to_i
      }
      prs.on("-c<img>", "--cdrom=<img>", "--iso=<img>", "set bootable iso image file"){|v|
        opts.cdrom.push(v)
      }
      prs.on("-d<dsk>", "--hdd=<dsk>", "--hda=<dsk>", "set harddisk file (must exist!)"){|v|
        opts.harddisk.push(v)
      }
      prs.on("-k<layout>", "--keyboard=<layout>", "set keyboard layout (i.e., 'de' for qwertz)"){|v|
        opts.keyboardlayout = v
      }
  }).parse!
  QVMProgram.new(opts, ARGV).launch
end
