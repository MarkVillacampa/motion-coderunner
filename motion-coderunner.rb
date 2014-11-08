#!/bin/ruby

rubymotion_dir = "/Library/RubyMotion"

raise "You don't seem to have RubyMotion installed" unless Dir.exist?(rubymotion_dir)

require "#{rubymotion_dir}/lib/motion/version.rb"

filename = ARGV[0]

if Dir.exist? ARGV[2]
  extra_frameworks = []
  filedir = ARGV[2]
else
  extra_frameworks = ARGV[2].split(' ')
  filedir = ARGV[3]
end

osx_version = `sw_vers -productVersion`.strip.match(/((\d+).(\d+))/)[0]

mrep = "MREP_THERE_IS_ONLY_ONE_FILE"

frameworks = %W{AppKit Foundation CoreGraphics CoreServices ApplicationServices AudioToolbox AudioUnit CoreData QuartzCore Security CoreAudio DiskArbitration OpenGL ImageIO CoreText CoreFoundation CFNetwork SystemConfiguration IOSurface Accelerate CoreVideo}.concat(extra_frameworks)
frameworks_flags = frameworks.map { |f| "-framework #{f}"}.join(' ')


frameworks_stubs = frameworks.map { |framework|
  stub_file = "#{rubymotion_dir}/data/osx/#{osx_version}/MacOSX/#{framework}_stubs.o"
  File.exist?(stub_file) ? %Q{"#{stub_file}"} : nil
}.compact.join(' ')

bs_frameworks = (frameworks + ['RubyMotion']).map { |framework|
  bs_file ="#{rubymotion_dir}/data/osx/#{osx_version}/BridgeSupport/#{framework}.bridgesupport"
  File.exist?(bs_file) ? %Q{--uses-bs "#{bs_file}"} : nil
}.join(' ')


#########################
#### BUILD ruby file ####
#########################

env = %Q{ /usr/bin/env VM_PLATFORM="MacOSX" VM_KERNEL_PATH="#{rubymotion_dir}/data/osx/#{osx_version}/MacOSX/kernel-x86_64.bc" VM_OPT_LEVEL="0" /usr/bin/arch -arch x86_64 }
system %Q{ #{env} #{rubymotion_dir}/bin/ruby #{bs_frameworks} --emit-llvm "/tmp/#{filename}.x86_64.s" #{mrep} "#{filename}" }

system %Q{ clang -fexceptions -c -arch x86_64 "/tmp/#{filename}.x86_64.s" -o "/tmp/#{filename}.x86_64.o" }

#######################
#### BUILD main.mm ####
#######################

main_txt = <<EOS
#import <Foundation/Foundation.h>
extern "C" {
    void rb_define_global_const(const char *, void *);
    void rb_rb2oc_exc_handler(void);
    void rb_exit(int);
    void ruby_init(void);
    void ruby_init_loadpath(void);
    void ruby_script(const char *);
    void *rb_vm_top_self(void);
    void #{mrep}(void *, void *);
}

int
main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    static bool initialized = false;
    if (!initialized) {
        ruby_init();
        ruby_init_loadpath();
        if (argc > 0) {
            const char *progname = argv[0];
            ruby_script(progname);
        }
        void *self = rb_vm_top_self();

        rb_define_global_const(\"RUBYMOTION_ENV\", @\"development\");
        rb_define_global_const(\"RUBYMOTION_VERSION\", @\"#{Motion::Version}\");

        #{mrep}(self, 0);

        initialized = true;
    }

    [pool release];
    rb_exit(0);
    return 0;
}
EOS

File.open("/tmp/main.mm", 'w') { |io| io.write(main_txt) }
system "clang++ /tmp/main.mm -o /tmp/main.o -arch x86_64 -O0 -fexceptions -fblocks -fmodules -c"

#########################
#### LINK EXECUTABLE ####
#########################

kernel_o = "#{rubymotion_dir}/data/osx/#{osx_version}/MacOSX/kernel.o"
kernel_o = File.exists?(kernel_o) ? kernel_o : ''

system %Q{ clang++ -o /tmp/a.out /tmp/main.o #{kernel_o} "/tmp/#{filename}.x86_64.o" -arch x86_64 -L#{rubymotion_dir}/data/osx/#{osx_version}/MacOSX -lrubymotion-static -lobjc -licucore #{frameworks_flags} }
puts "/tmp/a.out"
