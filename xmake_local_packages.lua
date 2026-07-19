-- Local overrides for third-party xmake-repo package recipes.
--
-- gamenetworkingsockets (upstream xmake-repo, checked 2026-07-12):
-- Its on_install() for v1.6.0+ always does:
--     local openssl = package:dep("openssl")
--     if openssl then
--         table.insert(configs, "-DOPENSSL_ROOT_DIR=" .. openssl:installdir())
--         ...
--     end
-- On this machine the project's "openssl" requirement (no version pin)
-- resolves via system pkgconfig (openssl 3.6.3, see `checking for openssl ...
-- pkgconfig::openssl 3.6.3` in `xmake config -vD` output). For a
-- system-resolved package, package:installdir() is NOT the real system
-- prefix -- it still returns the deterministic (but never populated) cache
-- path for the package's nominal/default version (1.1.1-w, the newest
-- entry in this repo's add_versions list), because that path is computed
-- from the requested version string, independent of how the package was
-- actually fetched. Passing that empty directory as -DOPENSSL_ROOT_DIR
-- makes CMake's FindOpenSSL search ONLY there and fail with:
--   "Could NOT find OpenSSL ... (missing: OPENSSL_CRYPTO_LIBRARY) (found version 3.6.3)"
-- even though a fully usable system OpenSSL 3.6.3 exists at /usr.
--
-- Fix: only pass -DOPENSSL_ROOT_DIR / -DOPENSSL_USE_STATIC_LIBS=ON when
-- openssl was actually built by xmake (not openssl:is_system()). This is
-- the exact guard already used for the same package name in other
-- xmake-repo recipes (e.g. packages/a/aws-c-cal, packages/c/cpp-httplib,
-- packages/b/boost) -- our local xmake-repo mirror's copy of the
-- gamenetworkingsockets recipe just predates that fix being applied there.
-- The system OpenSSL 3.6.3 install here has no static (.a) libs, so when
-- system-resolved we force OPENSSL_USE_STATIC_LIBS=OFF instead of ON.
package("gamenetworkingsockets")
    set_homepage("https://github.com/ValveSoftware/GameNetworkingSockets")
    set_description("Reliable & unreliable messages over UDP. Robust message fragmentation & reassembly. P2P networking / NAT traversal. Encryption. ")
    set_license("BSD-3-Clause")

    set_urls("https://github.com/ValveSoftware/GameNetworkingSockets/archive/$(version).tar.gz",
             "https://github.com/ValveSoftware/GameNetworkingSockets.git")

    add_versions("v1.6.0", "bddfe735d29ff2bbf186013a945ed57caaf4b79893eb7918c06c0f64955016f3")
    add_versions("v1.4.1", "1cfb2bf79c51a08ae4e8b7ff5e9c1266b43cfff6f53ecd3e7bc5e3fcb2a22503")
    add_versions("v1.4.0", "eca3b5684dbf81a3a6173741a38aa20d2d0a4d95be05cf88c70e0e50062c407b")
    add_versions("v1.3.0", "f473789ae8a8415dd1f5473793775e68a919d27eba18b9ba7d0a14f254afddf9")
    add_versions("v1.2.0", "768a7cec2491e34c824204c4858351af2866618ceb13a024336dc1df8076bef3")

    if is_plat("windows") then
        add_syslinks("ws2_32", "bcrypt")
        add_defines("_WINDOWS", "WIN32")
    else
        add_defines("POSIX", "LINUX")
        add_syslinks("pthread")
    end

    add_configs("webrtc", {description = "Enable P2P with Google's WebRTC.", default = false, type = "boolean"})
    add_configs("ice", {description = "Enable P2P with ICE.", default = true, type = "boolean"})

    on_load("windows", "linux", function(package)
        if package:version():gt("1.4.1") then
            package:add("deps", "protobuf-cpp")
            package:add("deps", "abseil")

            if package:config("ice") then
                package:add("defines", "STEAMNETWORKINGSOCKETS_ENABLE_ICE")
            end
        else
            package:add("deps", "protobuf-cpp <30")

            if package:config("webrtc") then
                package:add("deps", "abseil")
            end
        end

        if not package:is_plat("windows") then
            package:add("deps", "openssl")
        end

        if not package:config("shared") then
            package:add("defines", "STEAMNETWORKINGSOCKETS_STATIC_LINK")
        end
    end)

    on_install("windows|x86", "windows|x64", "linux", function (package)
        -- We need copy source codes to the working directory with short path on windows
        --
        -- Because the target name and source file path of this project are too long,
        -- it's absolute path exceeds the windows path length limit.
        --
        local oldir
        if is_host("windows") then
            local sourcedir = os.tmpdir() .. ".dir"
            os.tryrm(sourcedir)
            os.cp(os.curdir(), sourcedir)
            oldir = os.cd(sourcedir)
        end

        if package:version():le("1.4.1") then
            local configs = {}
            if package:config("shared") then
                configs.kind = "shared"
            end
            configs.webrtc = package:config("webrtc")
            os.cp(path.join(package:scriptdir(), "port", "xmake.lua"), "xmake.lua")
            import("package.tools.xmake").install(package, configs)
        else
            local configs = {}
            table.insert(configs, "-DCMAKE_BUILD_TYPE=" .. (package:is_debug() and "Debug" or "Release"))
            table.insert(configs, "-DBUILD_STATIC_LIB=" .. (not package:config("shared") and "ON" or "OFF"))
            table.insert(configs, "-DBUILD_SHARED_LIB=" .. (package:config("shared") and "ON" or "OFF"))
            table.insert(configs, "-DENABLE_ICE=" .. (package:config("ice") and "ON" or "OFF"))
            table.insert(configs, "-DUSE_STEAMWEBRTC=" .. (package:config("webrtc") and "ON" or "OFF"))

            local protobuf = package:dep("protobuf-cpp")
            if protobuf then
                table.insert(configs, "-DProtobuf_USE_STATIC_LIBS=" .. (protobuf:config("shared") and "OFF" or "ON"))
            end

            if not package:is_plat("windows") then
                local openssl = package:dep("openssl")
                if openssl then
                    if openssl:is_system() then
                        -- system-resolved (pkgconfig/etc): installdir() is not the real
                        -- prefix, don't pass it as a hint -- let CMake's FindOpenSSL find
                        -- it on standard system search paths, and don't require static
                        -- libs since Arch's openssl package ships shared-only.
                        table.insert(configs, "-DOPENSSL_USE_STATIC_LIBS=OFF")
                    else
                        table.insert(configs, "-DOPENSSL_ROOT_DIR=" .. openssl:installdir())
                        table.insert(configs, "-DOPENSSL_USE_STATIC_LIBS=" .. (openssl:config("shared") and "OFF" or "ON"))
                    end
                end
            else
                table.insert(configs, "-DUSE_CRYPTO=BCrypt")
            end

            import("package.tools.cmake").install(package, configs)

            local gns = path.join(package:installdir("include"), "GameNetworkingSockets", "steam")
            os.cp(gns, path.join(package:installdir("include"), "steam"))
            os.tryrm(path.join(package:installdir("include"), "GameNetworkingSockets"))
        end

        if oldir then
            os.cd(oldir)
        end
    end)

    on_test(function (package)
        assert(package:has_cxxfuncs("GameNetworkingSockets_Kill()", {includes = "steam/steamnetworkingsockets.h"}))
    end)
package_end()
