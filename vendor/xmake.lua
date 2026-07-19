target("RED4ext.SDK")
    set_kind("static")
    set_group("vendor")
    add_files("RED4ext.SDK/src/**.cpp")
    add_headerfiles("RED4ext.SDK/include/**.hpp")
    add_includedirs("RED4ext.SDK/include/", { public = true })
    -- The 2.31 SDK's GpuApi headers include <D3D12MemAlloc.h>, vendored inside the
    -- submodule; upstream CMake exposes this dir on its targets the same way.
    add_includedirs("RED4ext.SDK/vendor/D3D12MemAlloc/", { public = true })
    on_install(function() end)
