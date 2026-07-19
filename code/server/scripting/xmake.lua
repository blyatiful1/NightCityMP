target("Server.Scripting")
    set_kind("phony")
    set_group("Server")
    add_extrafiles("SdkGenerator/*.cs")
    add_extrafiles("../native/Scripting/I*.h")

    set_policy('build.fence', true)

    local function dirname(path)
        path = path:gsub("[\\/]+$", "")
        return path:match("[^\\/]+$")
    end

    local function get_plugins(root, exclude)
        local function is_excluded(dir)
            for _, path in ipairs(exclude) do
                if dir:match(path .. "$") then
                    return true
                end
            end
            return false
        end
        local plugins = {}

        root = path.join(root, "*")
        for _, dir in ipairs(os.dirs(root)) do
            local proj = path.join(dir, dirname(dir) .. ".csproj")

            if dir:match("System$") and os.exists(proj) and not is_excluded(dir, exclude) then
                table.insert(plugins, dirname(dir))
            end
        end
        return plugins
    end

    on_build(function (target, opt)
        import("core.project.depend")
        import("utils.progress")

        -- This machine only has the .NET 9 SDK/runtime installed, but the
        -- SdkGenerator/CyberpunkSdk C# tools below target net8.0. Without
        -- this, `dotnet run`/the published apphost fails at launch with:
        --   "You must install or update .NET to run this application. ...
        --    Framework: 'Microsoft.NETCore.App', version '8.0.0' ...
        --    The following frameworks were found: 9.0.17"
        -- DOTNET_ROLL_FORWARD=LatestMajor is the official dotnet-host env
        -- var that allows rolling forward across major versions (9.x
        -- satisfies a net8.0 request) instead of the default Minor policy,
        -- which refuses to cross major version boundaries.
        --
        -- NOTE: this must be passed via os.runv's opt.envs on the specific
        -- `dotnet run` call, NOT set process-wide with os.setenv. Under
        -- parallel (-j) builds, other concurrently-scheduled xmake
        -- coroutines (toolchain/package probes running in the same OS
        -- process) call os.setenvs()/os.getenvs() for their own tool
        -- detection and silently clobber process-wide env changes made
        -- here before the blocking `dotnet build`/`dotnet run` subprocess
        -- even starts -- verified empirically: env dumped immediately
        -- after os.setenv shows the var, but a dump taken after the first
        -- `os.run("dotnet build ...")` call no longer has it.
        local dotnet_envs = {DOTNET_ROLL_FORWARD = "LatestMajor"}

        local dependfile = target:dependfile("scripting")

        --depend.on_changed(function ()
            local output = path.join(target:targetdir(), "plugins")
            local sdk_output = path.join(target:targetdir(), "sdk")
            local script = target:scriptdir()
            local sdk_gen_proj = path.join(script, "SdkGenerator", "SdkGenerator.csproj")
            local sdk_proj = path.join(script, "CyberpunkSdk", "CyberpunkSdk.csproj")

            local files = {}
            for _, file in ipairs(target:extrafiles()) do
                if file:endswith(".h") then
                    table.insert(files, file)
                end
            end

            -- Build SDK
            progress.show(opt.progress, "${color.build.target}build codegen")
            os.runv("dotnet", {"build", sdk_gen_proj}, {envs = dotnet_envs})
            progress.show(opt.progress, "${color.build.target}codegen sdk")
            os.runv("dotnet", table.join({"run", "--project", sdk_gen_proj, "--"}, files), {envs = dotnet_envs})
            progress.show(opt.progress, "${color.build.target}build sdk")
            os.runv("dotnet", {"publish", sdk_proj, "-o", sdk_output}, {envs = dotnet_envs})

            -- Build plugins
            local mode = is_mode("debug") and "Debug" or "Release"
            -- EmoteSystem ships a web Admin/ dashboard built via an MSBuild
            -- BeforeTargets="Build;Publish" hook that shells out to
            -- `pnpm install` / `pnpm run build` (see EmoteSystem.csproj).
            -- This build machine has no node/npm/pnpm/corepack installed
            -- (and installing one is out of scope for this fix). The
            -- Admin dashboard is a web UI bundle copied into the plugin's
            -- publish output (Admin\dist -> assets\...), not core gameplay
            -- logic, so excluding it here (same mechanism already used for
            -- VehicleSystem) unblocks Server.Scripting -> Server.Loader.
            -- Revert this exclusion once a pnpm toolchain is available.
            local exclude = {"VehicleSystem", "EmoteSystem"}
            local plugins = get_plugins(script, exclude)

            for _, name in ipairs(plugins) do
                local proj = path.join(script, name, name .. ".csproj")
                local label = string.lower(name:sub(1, -7))

                progress.show(opt.progress, "${color.build.target}build " .. label)
                os.runv("dotnet", {"publish", proj, "-c", mode, "-o", path.join(output, name)}, {envs = dotnet_envs})
            end
	--[[	end,
		{
			dependfile = dependfile,
			files = target:extrafiles(),
			changed = target:is_rebuilt()
		})]]--
    end)

    on_install(function (target)
        local src_plugins = path.join(target:targetdir(), "plugins")
        local dest_plugins = path.join(target:installdir("launcher"), "server", "plugins")

        print("Installing plugins from " .. src_plugins .. " to " .. dest_plugins)

        if os.isdir(dest_plugins) then
            os.rmdir(dest_plugins)
        end

        os.cp(src_plugins, dest_plugins)
        os.cp(path.join(target:targetdir(), "sdk", "*"), path.join(target:installdir("launcher"), "server"))

        -- Iterate over subdirectories in the destination plugins folder
        for _, dir in ipairs(os.dirs(path.join(dest_plugins, "*"))) do
            local dir_name = path.basename(dir)

            -- Get all files in the current subdirectory
            local files = os.files(path.join(dir, "*"))

            -- Iterate over files and delete those that don't match the directory name
            for _, file in ipairs(files) do
                local file_name = path.basename(file)
                local file_name_without_ext = path.basename(file):gsub("%..*$", "")
                local file_ext = path.extension(file)

                if file_name_without_ext ~= dir_name or file_ext == ".pdb" then
                    os.rm(file)
                end
            end
        end
    end)
