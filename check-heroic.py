#!/usr/bin/env python3
"""Minimal dependency-free Vulkan test: create an instance and enumerate GPUs.

It verifies inside a Flatpak sandbox (for example Heroic) that the ICD selected
by VK_DRIVER_FILES loads and that /dev/dri is accessible.

Usage:  python3 check-heroic.py
"""
import ctypes
import os
import sys

VK_SUCCESS = 0
VK_STRUCTURE_TYPE_APPLICATION_INFO = 0
VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1


class VkApplicationInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_uint32),
        ("pNext", ctypes.c_void_p),
        ("pApplicationName", ctypes.c_char_p),
        ("applicationVersion", ctypes.c_uint32),
        ("pEngineName", ctypes.c_char_p),
        ("engineVersion", ctypes.c_uint32),
        ("apiVersion", ctypes.c_uint32),
    ]


class VkInstanceCreateInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_uint32),
        ("pNext", ctypes.c_void_p),
        ("flags", ctypes.c_uint32),
        ("pApplicationInfo", ctypes.POINTER(VkApplicationInfo)),
        ("enabledLayerCount", ctypes.c_uint32),
        ("ppEnabledLayerNames", ctypes.c_void_p),
        ("enabledExtensionCount", ctypes.c_uint32),
        ("ppEnabledExtensionNames", ctypes.c_void_p),
    ]


def main():
    print("VK_DRIVER_FILES   =", os.environ.get("VK_DRIVER_FILES", "(not set)"))
    print("VK_ICD_FILENAMES  =", os.environ.get("VK_ICD_FILENAMES", "(not set)"))
    print("LD_LIBRARY_PATH   =", os.environ.get("LD_LIBRARY_PATH", "(not set)"))
    print("/dev/dri          =", "yes" if os.path.isdir("/dev/dri") else "NO")

    try:
        vk = ctypes.CDLL("libvulkan.so.1")
    except OSError as exc:
        print("ERROR: cannot load libvulkan.so.1:", exc)
        return 1

    vk.vkCreateInstance.restype = ctypes.c_int
    vk.vkEnumeratePhysicalDevices.restype = ctypes.c_int

    app = VkApplicationInfo(
        sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pNext=None,
        pApplicationName=b"check-heroic",
        applicationVersion=1,
        pEngineName=b"none",
        engineVersion=1,
        apiVersion=(1 << 22),
    )
    info = VkInstanceCreateInfo(
        sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        pNext=None,
        flags=0,
        pApplicationInfo=ctypes.pointer(app),
        enabledLayerCount=0,
        ppEnabledLayerNames=None,
        enabledExtensionCount=0,
        ppEnabledExtensionNames=None,
    )

    inst = ctypes.c_void_p()
    rc = vk.vkCreateInstance(ctypes.byref(info), None, ctypes.byref(inst))
    if rc != VK_SUCCESS:
        print(f"ERROR: vkCreateInstance failed (VkResult {rc})")
        return 1

    count = ctypes.c_uint32(0)
    rc = vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(count), None)
    if rc != VK_SUCCESS:
        print(f"ERROR: vkEnumeratePhysicalDevices failed (VkResult {rc})")
        return 1

    print(f"Vulkan GPUs found: {count.value}")
    if count.value == 0:
        print("ERROR: no GPU (bad ICD? no /dev/dri?)")
        return 1

    devs = (ctypes.c_void_p * count.value)()
    vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(count), devs)

    vk.vkGetPhysicalDeviceProperties.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    for i in range(count.value):
        buf = ctypes.create_string_buffer(1024)
        vk.vkGetPhysicalDeviceProperties(devs[i], buf)
        name = buf.raw[20:20 + 256].split(b"\0", 1)[0].decode(errors="replace")
        print(f"  [{i}] {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
