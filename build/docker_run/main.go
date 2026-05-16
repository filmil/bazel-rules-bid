package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bitfield/script"
)

var (
	container        = flag.String("container", "", "The name of the container to run")
	dirReference     = flag.String("dir-reference", "", "Some file in the current directory, e.g. the first file of inputs, for figuring out directories")
	cdToDirReference = flag.Bool("cd-to-dir-reference", false, "If set, the script will CD into the reference directory before executing the command.")
	scratchDir       = flag.String("scratch-dir", "", "A docker expression host_dir:container_dir that will be mounted read-write")
	sourceDir        = flag.String("source-dir", "", "The absolute path to the source dir, used for mounting source files.")
	envs             = flag.String("envs", "", "Comma-separated key value pairs for env variables.")
	mounts           = flag.String("mounts", "", "Comma-separated key value pairs for mounts.")
	tools            = flag.String("tools", "", "Comma-separated list of tool files")
	freeargs         = flag.String("freeargs", "", "Comma-separated list of free flags to apply")
	srcMount         = flag.String("src-mount", "/src", "OBSOLETE: The writable work directory to mount")
	srcDirHint       = flag.String("src-dir-hint", "", "this should be a full path, relative to execroot, for a file in the source dir.")
)

func resolveWorkspace(hint string) (string, error) {
	curr, err := filepath.Abs(hint)
	if err != nil {
		return "", err
	}
	if info, err := os.Stat(curr); err == nil && !info.IsDir() {
		curr = filepath.Dir(curr)
	}

	for {
		for _, marker := range []string{"WORKSPACE", "WORKSPACE.bazel", "MODULE", "MODULE.bazel", "REPO.bazel"} {
			if _, err := os.Stat(filepath.Join(curr, marker)); err == nil {
				return curr, nil
			}
		}
		parent := filepath.Dir(curr)
		if parent == curr {
			break
		}
		curr = parent
	}
	return "", fmt.Errorf("workspace not found for %s", hint)
}

func main() {
	flag.Parse()

	if *container == "" {
		fmt.Fprintln(os.Stderr, "Flag --container=... is required")
		os.Exit(2)
	}
	if *dirReference == "" {
		fmt.Fprintln(os.Stderr, "Flag --dir-reference=... is required")
		os.Exit(3)
	}

	if os.Getenv("DEBUG") == "true" {
		fmt.Printf("PATH: %s\n", os.Getenv("PATH"))
	}

	pwd, _ := os.Getwd()
	outputDir := filepath.Dir(*dirReference)
	absOutputDir, _ := filepath.Abs(outputDir)

	buildRoot := pwd
	if idx := strings.Index(pwd, "/_bazel_"); idx != -1 {
		buildRoot = pwd[:idx]
	}

	cacheDir := pwd
	if idx := strings.Index(pwd, "/bazel/_bazel_"); idx != -1 {
		cacheDir = pwd[:idx]
	}
	outputRoot := filepath.Join(cacheDir, "bazel")

	homeDir := buildRoot
	if idx := strings.Index(buildRoot, "/.cache/"); idx != -1 {
		homeDir = buildRoot[:idx]
	}

	uid := os.Getuid()
	gid := os.Getgid()

	dockerArgs := []string{"run", "--rm", "--interactive"}
	dockerArgs = append(dockerArgs, "-u", fmt.Sprintf("%d:%d", uid, gid))
	dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:%s:rw", outputRoot, outputRoot))
	dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:%s:rw", homeDir, homeDir))

	if *tools != "" {
		tempToolsDir, err := os.MkdirTemp(absOutputDir, "tools-")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to create temp tools dir: %v\n", err)
			os.Exit(1)
		}
		for _, tf := range strings.Split(*tools, ",") {
			if tf == "" {
				continue
			}
			_, err := script.File(tf).WriteFile(filepath.Join(tempToolsDir, filepath.Base(tf)))
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to copy tool %s: %v\n", tf, err)
			}
		}
		dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:/tools:ro", tempToolsDir))
	}

	if *envs != "" {
		for _, e := range strings.Split(*envs, ",") {
			if e != "" {
				dockerArgs = append(dockerArgs, "-e", e)
			}
		}
	}

	if *mounts != "" {
		for _, m := range strings.Split(*mounts, ",") {
			if m != "" {
				dockerArgs = append(dockerArgs, "-v", m)
			}
		}
	}

	if *scratchDir != "" {
		hostDir := strings.Split(*scratchDir, ":")[0]
		if !filepath.IsAbs(hostDir) {
			hostDir = filepath.Join(pwd, hostDir)
		}
		os.MkdirAll(hostDir, 0777)
		os.Chmod(hostDir, 0777)
		dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:rw", *scratchDir))
	}

	if *freeargs != "" {
		for _, f := range strings.Split(*freeargs, ",") {
			if f != "" {
				dockerArgs = append(dockerArgs, f)
			}
		}
	}

	if *srcDirHint != "" {
		srcDir, err := resolveWorkspace(*srcDirHint)
		if err == nil {
			dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:%s:ro", srcDir, srcDir))
		}
	}

	githubRunnerSpecial := "/home/runner/.bazel"
	if _, err := os.Stat(githubRunnerSpecial); err == nil {
		dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("%s:%s:rw", githubRunnerSpecial, githubRunnerSpecial))
	}

	dockerArgs = append(dockerArgs, "-w", pwd)
	dockerArgs = append(dockerArgs, *container)

	cmdArgs := flag.Args()
	dockerArgs = append(dockerArgs, "bash", "-c", strings.Join(cmdArgs, " "))

	dockerPath, err := exec.LookPath("docker")
	if err != nil {
		// Try common locations if not in PATH
		for _, p := range []string{"/usr/bin/docker", "/usr/local/bin/docker"} {
			if _, err2 := os.Stat(p); err2 == nil {
				dockerPath = p
				err = nil
				break
			}
		}
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: docker not found in PATH or common locations. PATH=%s\n", os.Getenv("PATH"))
		os.Exit(1)
	}

	if os.Getenv("DEBUG") == "true" {
		fmt.Printf("Running: %s %s\n", dockerPath, strings.Join(dockerArgs, " "))
	}

	script.Exec("sync").Wait()

	cmd := exec.Command(dockerPath, dockerArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err = cmd.Run()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		fmt.Fprintf(os.Stderr, "Error running docker: %v\n", err)
		os.Exit(1)
	}
}
