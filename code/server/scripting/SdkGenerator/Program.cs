using CppSharp;
using CppSharp.AST;
using CppSharp.Generators;
using System.Runtime.InteropServices;

internal class CyberpunkSdk : ILibrary
{
    private string Module { get; set; }
    private string OutputPath { get; set; }
    private string SourcePath { get; set; }
    private string[] FileNames { get; set; }

    internal CyberpunkSdk(string module, string outputPath, string sourcePath, string[] fileNames)
    {
        Module = module;
        OutputPath = outputPath;
        SourcePath = sourcePath;
        FileNames = fileNames;
    }

    public void Postprocess(Driver driver, ASTContext ctx)
    {
    }

    public void Preprocess(Driver driver, ASTContext ctx)
    {
    }

    public void Setup(Driver driver)
    {
        var options = driver.Options;
        options.OutputDir = OutputPath;
        options.GeneratorKind = GeneratorKind.CSharp;

        var parserOptions = driver.ParserOptions;
        parserOptions.AddDefines("WIN32");
        // MSVC 14.44+ STL hard-refuses parsers older than Clang 19 (STL1000 in
        // yvals_core.h); CppSharp 1.1.5 bundles Clang 16. This is the STL's own
        // documented escape hatch. Our parsed headers are plain interface files,
        // so the version gap is tolerable. CppSharp 1.2 (Clang 19) is not a drop-in
        // (runtimes-only NuGet layout, net9+/net10+ split per platform).
        parserOptions.AddDefines("_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH");
        parserOptions.AddDefines("CPPSHARP_GENERATOR");

        var module = options.AddModule(Module);
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            module.SharedLibraryName = "Server.Native.dll";
        else
            module.SharedLibraryName = "Server.Native";

        module.IncludeDirs.Add(SourcePath);

        foreach (var file in FileNames)
        {
            module.Headers.Add(file);
        }
    }

    public void SetupPasses(Driver driver)
    {

    }
}

internal class Program
{
    private static string GetGitRoot()
    {
        string gitFolderPath = LibGit2Sharp.Repository.Discover(Directory.GetCurrentDirectory());
        if (gitFolderPath == null)
            throw new Exception("This code should be ran from a Git repository!");

        // Repository.Info.WorkingDirectory resolves the actual checkout root,
        // including linked git worktrees. For a worktree the ".git" file points at
        // a private gitdir under <main>/.git/worktrees/<name>/; naively trimming
        // ".git" from that path yields the MAIN repo root and makes codegen write
        // into the wrong tree. In a normal CI clone this equals the repo root, so
        // behaviour there is unchanged.
        using var repo = new LibGit2Sharp.Repository(gitFolderPath);
        string workingDir = repo.Info.WorkingDirectory;
        if (string.IsNullOrEmpty(workingDir))
            throw new Exception("Repository has no working directory (bare repo?)!");

        return workingDir;
    }

    private static void Main(string[] args)
    {
        var fileNames = args.Select(arg => Path.GetFileName(arg)).ToArray();

        try
        {
            string root = GetGitRoot();
            string output = Path.Combine(root, @"code/server/scripting/CyberpunkSdk");
            string source = Path.Combine(root, @"code/server/native/Scripting");

            ConsoleDriver.Run(new CyberpunkSdk("CyberpunkSdk.Internal", output, source, fileNames));
            // NOTE: the loader-side ServerAPI binding (code/server/loader/CyberpunkMp.cs)
            // is NO LONGER generated here. CppSharp emits Itanium (Clang) mangled
            // DllImport EntryPoints regardless of target platform, so a generated
            // binding can never resolve the MSVC-mangled exports of a Windows-built
            // Server.Native.dll. The loader now ships a hand-written CyberpunkMp.cs that
            // binds to the plain, unmangled extern "C" ServerAPI shim
            // (code/server/native/Scripting/ServerAPIShim.cpp), whose export names are
            // identical under both the Linux (Itanium) and Windows (MSVC) toolchains.

            //string sdkFile = Path.Combine(output, "CyberpunkSdk.Internal.cs");

            //string text = File.ReadAllText(sdkFile);

            /*if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                text = text.Replace("Server.exe.dll", "Server.exe");
            else
                text = text.Replace("DllImport(\"Server\"", "DllImport(\"../Server\"");*/
           
            //File.WriteAllText(sdkFile, text);
        }
        catch(Exception e)
        {
            Console.WriteLine(e);
        }
    }
}