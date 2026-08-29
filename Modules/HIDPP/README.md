# HIDPP

HIDPP contains the platform-independent Logitech HID++ protocol support used by LinearMouse. It provides report transport, receiver-slot routing, feature discovery, Adjustable DPI, and Hi-Res Wheel commands.

Platform-specific device wrappers conform to `HIDPPDeviceIO`; the module does not depend on LinearMouse or PointerKit.
