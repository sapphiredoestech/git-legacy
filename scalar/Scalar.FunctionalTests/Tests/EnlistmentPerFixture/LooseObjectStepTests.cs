using NUnit.Framework;
using Scalar.FunctionalTests.FileSystemRunners;
using Scalar.FunctionalTests.Properties;
using Scalar.FunctionalTests.Tools;
using Scalar.Tests.Should;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Scalar.FunctionalTests.Tests.EnlistmentPerFixture
{
    [TestFixtureSource(typeof(TestsWithEnlistmentPerFixture), nameof(TestsWithEnlistmentPerFixture.MaintenanceMode))]
    [Category(Categories.Maintenance)]
    public class LooseObjectStepTests : TestsWithEnlistmentPerFixture
    {
        private const string TempPackFolder = "tempPacks";
        private FileSystemRunner fileSystem;
        private Settings.MaintenanceMode maintenanceMode;

        // Set forcePerRepoObjectCache to true to avoid any of the tests inadvertently corrupting
        // the cache
        public LooseObjectStepTests(Settings.MaintenanceMode maintenanceMode)
            : base(forcePerRepoObjectCache: true, skipFetchCommitsAndTreesDuringClone: false, fullClone: false)
        {
            this.fileSystem = new SystemIORunner();
            this.maintenanceMode = maintenanceMode;
        }

        private string GitObjectRoot => ScalarHelpers.GetObjectsRootFromGitConfig(this.Enlistment.RepoRoot);
        private string PackRoot => this.Enlistment.GetPackRoot(this.fileSystem);
        private string TempPackRoot => Path.Combine(this.PackRoot, TempPackFolder);

        [TestCase]
        [Order(1)]
        public void NoLooseObjectsDoesNothing()
        {
            this.Enlistment.Unregister();
            this.DeleteFiles(this.GetLooseObjectFiles());

            this.DeleteFiles(this.GetLooseObjectFiles());
            this.GetLooseObjectFiles().Count.ShouldEqual(0);
            int startingPackFileCount = this.CountPackFiles();

            this.RunLooseObjectsTask();

            this.GetLooseObjectFiles().Count.ShouldEqual(0);
            this.CountPackFiles().ShouldEqual(startingPackFileCount);
        }

        [TestCase]
        [Order(2)]
        public void RemoveLooseObjectsInPackFiles()
        {
            this.ClearAllObjects();

            // Copy and expand one pack
            this.ExpandOneTempPack(copyPackBackToPackDirectory: true);
            this.GetLooseObjectFiles().Count.ShouldBeAtLeast(1);
            this.CountPackFiles().ShouldEqual(1);

            // Cleanup should delete all loose objects, since they are in the packfile
            this.RunLooseObjectsTask();

            this.GetLooseObjectFiles().Count.ShouldEqual(0);
            this.CountPackFiles().ShouldEqual(1);
            this.GetLooseObjectFiles().Count.ShouldEqual(0);
            this.CountPackFiles().ShouldEqual(1);
        }

        [TestCase]
        [Order(3)]
        public void PutLooseObjectsInPackFiles()
        {
            this.ClearAllObjects();

            // Expand one pack, and verify we have loose objects
            this.ExpandOneTempPack(copyPackBackToPackDirectory: false);
            int looseObjectCount = this.GetLooseObjectFiles().Count();
            looseObjectCount.ShouldBeAtLeast(1);

            // This step should put the loose objects into a packfile
            this.RunLooseObjectsTask();

            this.GetLooseObjectFiles().Count.ShouldEqual(looseObjectCount);
            this.CountPackFiles().ShouldEqual(1);

            // Running the step a second time should remove the loose obects and keep the pack file
            this.RunLooseObjectsTask();

            this.GetLooseObjectFiles().Count.ShouldEqual(0);
            this.CountPackFiles().ShouldEqual(1);
        }

        [TestCase]
        [Order(4)]
        [Ignore("Wait until Git fixes corrupt loose objects. See #151")]
        public void CorruptLooseObjectIsDeleted()
        {
            this.ClearAllObjects();

            // Expand one pack, and verify we have loose objects
            this.ExpandOneTempPack(copyPackBackToPackDirectory: false);
            int looseObjectCount = this.GetLooseObjectFiles().Count();
            looseObjectCount.ShouldBeAtLeast(1, "Too few loose objects");

            // Create an invalid loose object
            string fakeBlobFolder = Path.Combine(this.GitObjectRoot, "00");
            string fakeBlob = Path.Combine(
                        fakeBlobFolder,
                        "01234567890123456789012345678901234567");
            this.fileSystem.CreateDirectory(fakeBlobFolder);
            this.fileSystem.CreateEmptyFile(fakeBlob);

            // This step should fail to place the objects, but
            // succeed in deleting the given file.
            this.RunLooseObjectsTask();

            this.fileSystem.FileExists(fakeBlob).ShouldBeFalse(
                   "Step failed to delete corrupt blob");
            this.CountPackFiles().ShouldEqual(0, "Incorrect number of packs after first loose object step");
            this.GetLooseObjectFiles().Count.ShouldEqual(
                looseObjectCount,
                "unexpected number of loose objects after step");

            // This step should create a pack.
            this.RunLooseObjectsTask();

            this.CountPackFiles().ShouldEqual(1, "Incorrect number of packs after second loose object step");
            this.GetLooseObjectFiles().Count.ShouldEqual(looseObjectCount);

            // This step should delete the loose objects
            this.RunLooseObjectsTask();

            this.GetLooseObjectFiles().Count.ShouldEqual(0, "Incorrect number of loose objects after third loose object step");
        }

        private void RunLooseObjectsTask()
        {
            if (this.maintenanceMode == Settings.MaintenanceMode.Scalar)
            {
                this.Enlistment.RunVerb("loose-objects");
            }
            else if (this.maintenanceMode == Settings.MaintenanceMode.Git)
            {
                this.Enlistment.RunMaintenanceTask("loose-objects", "-c pack.window=0 -c pack.depth=0 ");
            }
        }

        private void ClearAllObjects()
        {
            this.Enlistment.Unregister();

            // Delete/Move any starting loose objects and packfiles
            this.DeleteFiles(this.GetLooseObjectFiles());
            this.MovePackFilesToTemp();
            this.GetLooseObjectFiles().Count.ShouldEqual(0, "incorrect number of loose objects after setup");
            this.CountPackFiles().ShouldEqual(0, "incorrect number of packs after setup");
        }

        private List<string> GetLooseObjectFiles()
        {
            List<string> looseObjectFiles = new List<string>();
            foreach (string directory in Directory.GetDirectories(this.GitObjectRoot))
            {
                // Check if the directory is 2 letter HEX
                if (Regex.IsMatch(directory, @"[/\\][0-9a-fA-F]{2}$"))
                {
                    string[] files = Directory.GetFiles(directory);
                    looseObjectFiles.AddRange(files);
                }
            }

            return looseObjectFiles;
        }

        private void DeleteFiles(List<string> filePaths)
        {
            foreach (string filePath in filePaths)
            {
                File.Delete(filePath);
            }
        }

        private int CountPackFiles()
        {
            return Directory.GetFiles(this.PackRoot, "*.pack").Length;
        }

        private void MovePackFilesToTemp()
        {
            string[] files = Directory.GetFiles(this.PackRoot);
            foreach (string file in files)
            {
                string path2 = Path.Combine(this.TempPackRoot, Path.GetFileName(file));

                if (!File.Exists(path2))
                {
                    File.Move(file, path2);
                }
                else
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                    File.Delete(file);
                }
            }
        }

        private void ExpandOneTempPack(bool copyPackBackToPackDirectory)
        {
            // Find all pack files
            string[] packFiles = Directory.GetFiles(this.TempPackRoot, "*.pack");
            Assert.Greater(packFiles.Length, 0);

            List<FileInfo> fileInfos = packFiles.Select(file => new FileInfo(file))
                                                .ToList();
            fileInfos.Sort((f1, f2) => (int)(f2.Length - f1.Length));
            string packFile = fileInfos[0].FullName;

            // Send the contents of the packfile to unpack-objects to example the loose objects
            // Note this won't work if the object exists in a pack file which is why we had to move them
            using (FileStream packFileStream = File.OpenRead(packFile))
            {
                string output = GitProcess.InvokeProcess(
                    this.Enlistment.RepoRoot,
                    "unpack-objects",
                    new Dictionary<string, string>() { { "GIT_OBJECT_DIRECTORY", this.GitObjectRoot } },
                    inputStream: packFileStream).Output;
            }

            if (copyPackBackToPackDirectory)
            {
                // Copy the pack file back to packs
                string packFileName = Path.GetFileName(packFile);
                File.Copy(packFile, Path.Combine(this.PackRoot, packFileName));

                // Replace the '.pack' with '.idx' to copy the index file
                string packFileIndexName = packFileName.Replace(".pack", ".idx");
                File.Copy(Path.Combine(this.TempPackRoot, packFileIndexName), Path.Combine(this.PackRoot, packFileIndexName));
            }
        }
    }
}
