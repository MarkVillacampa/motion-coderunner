#!/bin/ruby

raise "You don't seem to have RubyMotion installed" unless Dir.exist? "/Library/RubyMotion/"

require '/Library/RubyMotion/lib/motion/version.rb'

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

frameworks_stubs = Dir.glob("/Library/RubyMotion/data/osx/#{osx_version}/BridgeSupport/*_stubs.o").map { |f| %Q{"#{f}"} }.join(' ')
bs_frameworks = Dir.glob("/Library/RubyMotion/data/osx/#{osx_version}/BridgeSupport/*.bridgesupport").map { |f| "--uses-bs #{f}"}.join(' ')

#########################
#### BUILD ruby file ####
#########################

env = %Q{ /usr/bin/env VM_PLATFORM="MacOSX" VM_KERNEL_PATH="/Library/RubyMotion/data/osx/#{osx_version}/MacOSX/kernel-x86_64.bc" VM_OPT_LEVEL="0" /usr/bin/arch -arch x86_64 }
system %Q{ #{env} /Library/RubyMotion/bin/ruby #{bs_frameworks} --emit-llvm "/tmp/#{filename}.x86_64.s" #{mrep} "#{filename}" }

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

frameworks = %W{AppKit Foundation CoreGraphics CoreServices ApplicationServices AudioToolbox AudioUnit CoreData QuartzCore Security CoreAudio DiskArbitration OpenGL ImageIO CoreText CoreFoundation CFNetwork SystemConfiguration IOSurface Accelerate CoreVideo}.concat(extra_frameworks)
frameworks_flags = frameworks.map { |f| "-framework #{f}"}.join(' ')

system %Q{ clang++ -o /tmp/a.out /tmp/main.o "/tmp/#{filename}.x86_64.o" -arch x86_64 -L/Library/RubyMotion/data/osx/#{osx_version}/MacOSX -lrubymotion-static -lobjc -licucore #{frameworks_flags} }
puts "/tmp/a.out"
