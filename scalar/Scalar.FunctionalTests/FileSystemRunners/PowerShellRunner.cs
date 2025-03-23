using Scalar.Tests.Should;
using System;
using System.IO;

namespace Scalar.FunctionalTests.FileSystemRunners
{
    public class PowerShellRunner : ShellRunner
    {
        private const string ProcessName = "powershell.exe";

        private static string[] missingFileErrorMessages = new string[]
        {
            "Cannot find path"
        };

        private static string[] invalidPathErrorMessages = new string[]
        {
            "Could not find a part of the path"
        };

        private static string[] moveDirectoryNotSupportedMessage = new string[]
        {
            "The request is not supported."
        };

        private static string[] fileUsedByAnotherProcessMessage = new string[]
        {
            "The process cannot access the file because it is being used by another process"
        };

        private static string[] permissionDeniedMessage = new string[]
        {
            "PermissionDenied"
        };

        protected override string FileName
        {
            get
            {
                return ProcessName;
            }
        }

        public override bool FileExists(string path)
        {
            string parentDirectory = Path.GetDirectoryName(path);
            string targetName = Path.GetFileName(path);

            // Use -force so that hidden items are returned as well
            string command = string.Format("-Command \"&{{ Get-ChildItem -force {0} | where {{$_.Attributes -NotLike '*Directory*'}} | where {{$_.Name -eq '{1}' }} }}\"", parentDirectory, targetName);
            string output = this.RunProcess(command).Trim();

            if (output.Length == 0 || output.Contains("PathNotFound") || output.Contains("ItemNotFound"))
            {
                return false;
            }

            return true;
        }

        public override string MoveFile(string sourcePath, string targetPath)
        {
            return this.RunProcess(string.Format("-Command \"& {{ Move-Item {0} {1} -force}}\"", sourcePath, targetPath));
        }

        public override string ReplaceFile(string sourcePath, string targetPath)
        {
            return this.RunProcess(string.Format("-Command \"& {{ Move-Item {0} {1} -force }}\"", sourcePath, targetPath));
        }

        public override string DeleteFile(string path)
        {
            return this.RunProcess(string.Format("-Command \"& {{ Remove-Item {0} }}\"", path));
        }

        public override string ReadAllText(string path)
        {
            string output = this.RunProcess(string.Format("-Command \"& {{ Get-Content -Raw {0} }}\"", path), errorMsgDelimeter: "\r\n");

            // Get-Content insists on sticking a trailing "\r\n" at the end of the output that we need to remove
            output.Length.ShouldBeAtLeast(2, $"File content was not long enough for {path}");
            output.Substring(output.Length - 2).ShouldEqual("\r\n");
            output = output.Remove(output.Length - 2, 2);

            return output;
        }

        public override void AppendAllText(string path, string contents)
        {
            this.RunProcess(string.Format("-Command \"&{{ Out-File -FilePath {0} -InputObject '{1}' -Encoding ascii -Append -NoNewline}}\"", path, contents));
        }

        public override void CreateEmptyFile(string path)
        {
            this.RunProcess(string.Format("-Command \"&{{ New-Item -ItemType file {0}}}\"", path));
        }

        public override void CreateHardLink(string newLinkFilePath, string existingFilePath)
        {
            this.RunProcess(string.Format("-Command \"&{{ New-Item -ItemType HardLink -Path {0} -Value {1}}}\"", newLinkFilePath, existingFilePath));
        }

        public override void WriteAllText(string path, string contents)
        {
            this.RunProcess(string.Format("-Command \"&{{ Out-File -FilePath {0} -InputObject '{1}' -Encoding ascii -NoNewline}}\"", path, contents));
        }

        public override bool DirectoryExists(string path)
        {
            string command = string.Format("-Command \"&{{ Test-Path {0} -PathType Container }}\"", path);
            string output = this.RunProcess(command).Trim();

            if (output.Contains("True"))
            {
                return true;
            }

            return false;
        }

        public override void MoveDirectory(string sourcePath, string targetPath)
        {
            this.MoveFile(sourcePath, targetPath);
        }

        public override void RenameDirectory(string workingDirectory, string source, string target)
        {
            this.RunProcess(string.Format("-Command \"& {{ Rename-Item -Path {0} -NewName {1} -force }}\"", Path.Combine(workingDirectory, source), target));
        }

        public override void CreateDirectory(string path)
        {
            this.RunProcess(string.Format("-Command \"&{{ New-Item {0} -type directory}}\"", path));
        }

        public override string DeleteDirectory(string path)
        {
            return this.RunProcess(string.Format("-Command \"&{{ Remove-Item -Force -Recurse {0} }}\"", path));
        }

        public override string EnumerateDirectory(string path)
        {
            return this.RunProcess(string.Format("-Command \"&{{ Get-ChildItem {0} }}\"", path));
        }

        public override long FileSize(string path)
        {
            return long.Parse(this.RunProcess(string.Format("-Command \"&{{ (Get-Item {0}).length}}\"", path)));
        }

        public override void ChangeMode(string path, ushort mode)
        {
            throw new System.NotSupportedException();
        }

        public override IDisposable OpenFileAndWrite(string path, string data)
        {
            throw new System.NotSupportedException();
        }

        protected override string RunProcess(string command, string workingDirectory = "", string errorMsgDelimeter = "")
        {
            return base.RunProcess("-NoProfile " + command, workingDirectory, errorMsgDelimeter);
        }
    }
}
