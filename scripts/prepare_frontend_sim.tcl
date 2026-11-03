# Generate a local simulation wrapper from the actual checked-in FIFO IP.
set repo [file normalize [file join [file dirname [info script]] ..]]
set build [file join $repo tests frontend.sim]
file mkdir $build
cd $build
if {[catch {
  create_project -force frontend [file join $build project] -part xa7s50csga324-1Q
  set source [file join $repo flexray-interceptor-vivado.srcs sources_1 ip fifo_generator_0 fifo_generator_0.xci]
  set ch [open $source r]; set descriptor [read $ch]; close $ch
  regsub -all {"gen_directory": "[^"]*"} $descriptor "\"gen_directory\": \"[file join $build generated]\"" descriptor
  set copy [file join $build fifo_generator_0.xci]
  set ch [open $copy w]; puts -nonewline $ch $descriptor; close $ch
  import_ip -files $copy
  set ip [get_ips fifo_generator_0]
  if {[get_property CONFIG.Performance_Options $ip] ne "Standard_FIFO"} {error "Test requires configured Standard_FIFO"}
  if {[get_property CONFIG.Use_Embedded_Registers $ip]} {error "Adapter expects the configured unregistered FIFO output"}
  generate_target simulation $ip
  proc find_wrapper {directory} {
    foreach item [glob -nocomplain -directory $directory *] {
      if {[file isdirectory $item]} {
        set match [find_wrapper $item]
        if {$match ne ""} {return $match}
      } elseif {[file tail $item] eq "fifo_generator_0.v" && [file tail [file dirname $item]] eq "sim"} {return $item}
    }
    return ""
  }
  set wrapper [find_wrapper $build]
  if {$wrapper eq ""} {error "Generated simulation wrapper not found"}
  set ch [open [file join $build fifo_model_path.txt] w]; puts $ch $wrapper; close $ch
  puts "FRONTEND_FIFO_MODEL_PASS $wrapper"
  exit
} problem opts]} {
  puts stderr $problem
  puts stderr [dict get $opts -errorinfo]
  exit 1
}
