#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

class StatusNotifierWatcher(dbus.service.Object):
    def __init__(self, bus):
        bus_name = dbus.service.BusName("org.kde.StatusNotifierWatcher", bus=bus)
        super().__init__(bus_name, "/StatusNotifierWatcher")
        self.items = []

    @dbus.service.method("org.kde.StatusNotifierWatcher", in_signature="s", out_signature="")
    def RegisterStatusNotifierItem(self, service):
        print(f"[DummyWatcher] Registered Item: {service}")
        if service not in self.items:
            self.items.append(service)
            self.StatusNotifierItemRegistered(service)

    @dbus.service.method("org.kde.StatusNotifierWatcher", in_signature="s", out_signature="")
    def RegisterStatusNotifierHost(self, service):
        print(f"[DummyWatcher] Registered Host: {service}")
        self.StatusNotifierHostRegistered()

    @dbus.service.signal("org.kde.StatusNotifierWatcher", signature="s")
    def StatusNotifierItemRegistered(self, service):
        pass

    @dbus.service.signal("org.kde.StatusNotifierWatcher", signature="s")
    def StatusNotifierItemUnregistered(self, service):
        pass

    @dbus.service.signal("org.kde.StatusNotifierWatcher")
    def StatusNotifierHostRegistered(self):
        pass

    @dbus.service.signal("org.kde.StatusNotifierWatcher")
    def StatusNotifierHostUnregistered(self):
        pass

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        return self.GetAll(interface_name)[property_name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name == "org.kde.StatusNotifierWatcher":
            return {
                "RegisteredStatusNotifierItems": dbus.Array(self.items, signature="s"),
                "IsStatusNotifierHostRegistered": dbus.Boolean(True),
                "ProtocolVersion": dbus.Int32(0)
            }
        return {}

if __name__ == "__main__":
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    watcher = StatusNotifierWatcher(bus)
    print("[DummyWatcher] org.kde.StatusNotifierWatcher active on DBus.")
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
