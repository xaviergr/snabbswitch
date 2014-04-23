module(...,package.seeall)

local app        = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local config     = require("core.config")
local intel_app  = require("apps.intel.intel_app")
local lib        = require("core.lib")
local pcap       = require("apps.pcap.pcap")
local timer      = require("core.timer")
local pci        = require("lib.hardware.pci")
local vfio       = require("lib.hardware.vfio")
local vhost_user = require("apps.vhost.vhost_user")

function main ()
   print("Starting NFV...")
   local pciaddr = os.getenv("NFV_PCI") or error("No $NFV_PCI set.")
   local socket  = os.getenv("NFV_SOCKET") or error("No $NFV_SOCKET set.")
   local trace   = os.getenv("NFV_TRACE")
   pci.unbind_device_from_linux(pciaddr)
   local c = config.new()
   config.app(c, "vm", vhost_user.VhostUser, socket)
   config.app(c, "nic", intel_app.Intel82599, ([[{pciaddr='%s'}]]):format(pciaddr))
   if not trace then
      print("No trace file ($NFV_TRACE) configured.")
      config.link(c, "vm.tx -> nic.rx")
      config.link(c, "nic.tx -> vm.rx")
   else
      print("Tracing to files " .. trace .. ".{vm,nic}")
      config.app(c, "vm_tee", basic_apps.Tee)
      config.app(c, "nic_tee", basic_apps.Tee)
      config.app(c, "vm_trace", pcap.PcapWriter, trace..".vm")
      config.app(c, "nic_trace", pcap.PcapWriter, trace..".nic")
      config.link(c, "vm.tx -> vm_tee.input")
      config.link(c, "vm_tee.tx -> nic.rx")
      config.link(c, "vm_tee.tap -> vm_trace.input")
      config.link(c, "nic.tx -> nic_tee.input")
      config.link(c, "nic_tee.tx -> vm.rx")
      config.link(c, "nic_tee.tap -> nic_trace.input")
   end
   app.configure(c)
   -- Setup zero-copy
   local nic, vm = app.app_table.nic, app.app_table.vm
   nic:set_rx_buffer_freelist(vm.vring_transmit_buffers)
   timer.init()
   timer.activate(timer.new("report", app.report, 1e9, 'repeating'))
   print("Entering app.main()")
   app.main()
end

main()

