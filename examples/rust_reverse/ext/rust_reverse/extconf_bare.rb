# Use local rb_sys gem (only needed for developing in this repo)
$LOAD_PATH.unshift(File.expand_path("../../../../gem/lib", __dir__))

# We need to require mkmf *first* this since `rake-compiler` injects code here for cross compilation
require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("rust_reverse") do |r|
  r.extra_rustflags << "--cfg=rb_sys_use_stable_api_compiled_fallback"
end
