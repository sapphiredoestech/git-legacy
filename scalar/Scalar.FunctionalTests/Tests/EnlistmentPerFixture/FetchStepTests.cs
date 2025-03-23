using NUnit.Framework;
using Scalar.FunctionalTests.FileSystemRunners;
using Scalar.FunctionalTests.Properties;
using Scalar.FunctionalTests.Should;
using Scalar.FunctionalTests.Tools;
using Scalar.Tests.Should;
using System.IO;
using System.Linq;

namespace Scalar.FunctionalTests.Tests.EnlistmentPerFixture
{
    [TestFixtureSource(typeof(TestsWithEnlistmentPerFixture), nameof(TestsWithEnlistmentPerFixture.MaintenanceMode))]
    [Category(Categories.Maintenance)]
    [NonParallelizable]
    public class FetchStepTests : TestsWithEnlistmentPerFixture
    {
        private const string FetchCommitsAndTreesLock = "fetch-commits-trees.lock";

        private FileSystemRunner fileSystem;
        private Settings.MaintenanceMode maintenanceMode;

        public FetchStepTests(Settings.MaintenanceMode maintenanceMode)
        {
            this.fileSystem = new SystemIORunner();
            this.maintenanceMode = maintenanceMode;
        }

        [TestCase]
        public void FetchStepReleasesFetchLockFile()
        {
            this.RunFetchTask();
            string fetchCommitsLockFile = Path.Combine(
                ScalarHelpers.GetObjectsRootFromGitConfig(this.Enlistment.RepoRoot),
                "pack",
                FetchCommitsAndTreesLock);
            this.fileSystem.WriteAllText(fetchCommitsLockFile, this.Enlistment.EnlistmentRoot);
            fetchCommitsLockFile.ShouldBeAFile(this.fileSystem);

            this.fileSystem
                .EnumerateDirectory(this.Enlistment.GetPackRoot(this.fileSystem))
                .Split()
                .Where(file => string.Equals(Path.GetExtension(file), ".keep", FileSystemHelpers.PathComparison))
                .Count()
                .ShouldEqual(1, "Incorrect number of .keep files in pack directory");

            this.RunFetchTask();

            // Using FileShare.None ensures we test on both Windows, where WindowsFileBasedLock uses
            // FileShare.Read to open the lock file, and on Mac/Linux, where the .NET Core libraries
            // implement FileShare.None using flock(2) with LOCK_EX and thus will collide with our
            // Mac/Linux FileBasedLock implementations which do the same, should the FetchStep
            // have failed to release its lock.
            FileStream stream = new FileStream(fetchCommitsLockFile, FileMode.OpenOrCreate, FileAccess.Read, FileShare.None);
            stream.Dispose();
        }

        private void RunFetchTask()
        {
            if (this.maintenanceMode == Settings.MaintenanceMode.Scalar)
            {
                this.Enlistment.RunVerb("fetch");
            }
            else if (this.maintenanceMode == Settings.MaintenanceMode.Git)
            {
                this.Enlistment.RunMaintenanceTask("prefetch");
            }
        }
    }
}
