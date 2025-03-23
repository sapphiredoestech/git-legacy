using Scalar.FunctionalTests.Properties;
using Scalar.FunctionalTests.Tools;
using Scalar.Tests;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace Scalar.FunctionalTests
{
    public class Program
    {
        public static void Main(string[] args)
        {
            Properties.Settings.Default.Initialize();
            NUnitRunner runner = new NUnitRunner(args);
            runner.AddGlobalSetupIfNeeded("Scalar.FunctionalTests.GlobalSetup");

            if (runner.HasCustomArg("--no-shared-scalar-cache"))
            {
                Console.WriteLine("Running without a shared git object cache");
                ScalarTestConfig.NoSharedCache = true;
            }

            if (runner.HasCustomArg("--test-git-on-path"))
            {
                Console.WriteLine("Running tests against Git on path");
                ScalarTestConfig.TestGitOnPath = true;
            }

            if (runner.HasCustomArg("--test-scalar-on-path"))
            {
                Console.WriteLine("Running tests against Scalar on path");
                ScalarTestConfig.TestScalarOnPath = true;
            }

            string trace2Output = runner.GetCustomArgWithParam("--trace2-output");
            if (trace2Output != null)
            {
                Console.WriteLine($"Sending trace2 output to {trace2Output}");
                Environment.SetEnvironmentVariable("GIT_TRACE2_EVENT", trace2Output);
            }

            ScalarTestConfig.LocalCacheRoot = runner.GetCustomArgWithParam("--shared-scalar-cache-root");

            HashSet<string> includeCategories = new HashSet<string>();
            HashSet<string> excludeCategories = new HashSet<string>();

            // Run all GitRepoTests with sparse mode
            ScalarTestConfig.GitRepoTestsValidateWorkTree =
                new object[]
                {
                        new object[] { Settings.ValidateWorkingTreeMode.SparseMode },
                };

            // Run maintenance tests in both `scalar run` and `git maintenance run` modes
            ScalarTestConfig.MaintenanceMode =
                new object[]
                {
                    new object[] { Settings.MaintenanceMode.Scalar },
                    new object[] { Settings.MaintenanceMode.Git },
                };

            if (runner.HasCustomArg("--full-suite"))
            {
                Console.WriteLine("Running the full suite of tests");

                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    ScalarTestConfig.FileSystemRunners = FileSystemRunners.FileSystemRunner.AllWindowsRunners;
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ||
                         RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    ScalarTestConfig.FileSystemRunners = FileSystemRunners.FileSystemRunner.AllPOSIXRunners;
                }
            }
            else
            {
                ScalarTestConfig.FileSystemRunners = FileSystemRunners.FileSystemRunner.DefaultRunners;
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ||
                RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                excludeCategories.Add(Categories.WindowsOnly);
            }
            else
            {
                excludeCategories.Add(Categories.POSIXOnly);
            }

            // For now, run all of the tests not flagged as needing to be updated to work
            // with the non-virtualized solution
            excludeCategories.Add(Categories.NeedsUpdatesForNonVirtualizedMode);

            ScalarTestConfig.RepoToClone =
                runner.GetCustomArgWithParam("--repo-to-clone")
                ?? Properties.Settings.Default.RepoToClone;

            RunBeforeAnyTests();
            Environment.ExitCode = runner.RunTests(includeCategories, excludeCategories);

            if (Debugger.IsAttached)
            {
                Console.WriteLine("Tests completed. Press Enter to exit.");
                Console.ReadLine();
            }
        }

        private static void RunBeforeAnyTests()
        {
        }
    }
}
