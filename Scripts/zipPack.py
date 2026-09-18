#!/usr/bin/env python3
# 使用说明（Windows 11 / PowerShell 7）
# =====================================
# 依赖：Python 3.11、Git for Windows（git 需要在 PATH 中），无需第三方 Python 包。
# 脚本可放在任意位置，源目录参数必须提供，不再默认使用 ExternalMode。
#
# 基本格式：
#   python .\zipPack.py "源目录路径" [-o "输出名称或路径"] [--force]
# 下列示例假设当前 PowerShell 已进入脚本所在目录。
# 如果不在该目录，请把 .\zipPack.py 换成脚本的完整路径。
#
# 1. 默认命名：打包 D:\Data\B001，生成 D:\Data\B001.zip。
#   python .\zipPack.py "D:\Data\B001"
#
# 2. 使用相对源目录：打包 PowerShell 当前目录下的 B001。
#   python .\zipPack.py .\B001
#
# 3. 指定压缩包名称：生成 D:\Data\release.zip。
#   python .\zipPack.py "D:\Data\B001" -o "release.zip"
#   python .\zipPack.py "D:\Data\B001" --output "release"
#   -o 和 --output 等价；名称未以 .zip 结尾时，会自动追加 .zip。
#
# 4. 指定完整输出路径：输出目录 D:\Packages 必须已存在。
#   python .\zipPack.py "D:\Data\B001" -o "D:\Packages\release.zip"
#
# 5. 覆盖已有压缩包：默认拒绝覆盖，明确添加 --force 才会覆盖。
#   python .\zipPack.py "D:\Data\B001" -o "release.zip" --force
#
# 6. 明确使用本机 Python311 目录下的解释器：
#   & "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe" .\zipPack.py "D:\Data\B001"
#
# 7. 查看命令行帮助：
#   python .\zipPack.py --help
#
# 路径和压缩规则：
# - 含空格的路径请用双引号包裹。
# - 相对源路径以 PowerShell 当前目录为基准，不以脚本位置为基准。
# - 相对输出路径以源目录的上一层为基准；默认输出也是在源目录上一层。
# - 压缩包内部始终保留源目录名作为顶层目录。例如 release.zip 内仍是 B001/。
# - 排除各层级的 .git、.gitignore，以及匹配 Git 忽略规则的文件和目录。
#   即使文件已经被 Git 跟踪，只要匹配忽略规则，也会排除。
# - 普通非 Git 仓库目录也可以打包；仍需安装 Git 来解析忽略规则。
# - 不修改源目录；输出路径不得位于源目录内，输出目录必须已存在。
# - 不支持以符号链接或目录联接作为源目录；遇到未被排除的链接/联接会报错。
# - 打包后自动校验 ZIP 完整性，通过后才发布最终压缩包。
#
"""Package a directory without changing it. Requires Python 3.11 and Git.

PowerShell: python zipPack.py B001 [-o release.zip] [--force]
The source directory is required. Relative source paths use the current working
directory. Output defaults to SOURCE_NAME.zip beside the source directory.
Relative output paths also start at the source directory's parent.
"""

import argparse
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


def pack(source: Path, force: bool = False, output: Path | None = None) -> Path:
    source = source.absolute()
    source_info = source.lstat()
    if stat.S_ISLNK(source_info.st_mode) or (os.name == 'nt' and
            source_info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT):
        raise RuntimeError('The source must not be a symbolic link or junction.')
    source = source.resolve(strict=True)
    if not source.is_dir() or source.parent == source:
        raise ValueError('Source must be a directory other than a drive root.')
    if output is None:
        output = source.parent / (source.name + '.zip')
    else:
        output = Path(output)
        if not output.name or output.name in ('.', '..'):
            raise ValueError('Output must specify a ZIP filename.')
        if output.suffix.lower() != '.zip':
            output = output.with_name(output.name + '.zip')
        if not output.is_absolute():
            output = source.parent / output
    output = output.resolve()
    if output == source or source in output.parents:
        raise ValueError('Output must be outside the source directory to keep it unchanged.')
    if not output.parent.is_dir():
        raise ValueError(f'Output directory does not exist: {output.parent}')
    if output.exists() and not force:
        raise FileExistsError(f'{output} already exists; use --force to replace it.')
    git = shutil.which('git')
    if not git:
        raise RuntimeError('Git is required. Install Git for Windows and add it to PATH.')

    # Ignore inherited repository overrides; never refresh or write the source index.
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env['GIT_OPTIONAL_LOCKS'] = '0'
    command = [git, '-C', str(source)]
    temporary_zip = None
    with tempfile.TemporaryDirectory(prefix='zipPack-git-') as scratch:
        probe = subprocess.run(command + ['rev-parse', '--show-toplevel'],
                               env=env, capture_output=True)
        if probe.returncode:
            # Supply a disposable repository for ordinary non-repository folders.
            # The original directory is only used as the read-only work tree.
            git_dir = str(Path(scratch) / 'metadata')
            subprocess.run([git, 'init', '--bare', '--quiet', git_dir],
                           env=env, check=True, capture_output=True)
            command += ['--git-dir=' + git_dir, '--work-tree=' + str(source)]

        def ignored(paths):
            payload = b''.join(os.fsencode(p) + b'\0' for p in paths)
            result = subprocess.run(
                command + ['check-ignore', '--no-index', '-z', '--stdin'],
                input=payload, capture_output=True, env=env)
            if result.returncode not in (0, 1):
                raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
            return set(result.stdout.split(b'\0'))

        count = 0
        excluded = 0
        try:
            fd, temporary_zip = tempfile.mkstemp(
                prefix='.' + source.name + '-', suffix='.zip.tmp', dir=output.parent)
            os.close(fd)
            with zipfile.ZipFile(temporary_zip, 'w', zipfile.ZIP_DEFLATED,
                                 compresslevel=6, allowZip64=True,
                                 strict_timestamps=False) as archive:
                archive.mkdir(source.name + '/')

                def walk(folder):
                    nonlocal count, excluded
                    entries = sorted(folder.iterdir(), key=lambda p: p.name.casefold())
                    candidates = []
                    for entry in entries:
                        if entry.name.casefold() in ('.git', '.gitignore'):
                            excluded += 1
                        else:
                            candidates.append(entry)
                    if not candidates:
                        return
                    names = [p.relative_to(source).as_posix() for p in candidates]
                    skip = ignored(names)
                    for entry, relative in zip(candidates, names):
                        if os.fsencode(relative) in skip:
                            excluded += 1
                            continue
                        info = entry.lstat()
                        if stat.S_ISLNK(info.st_mode) or (os.name == 'nt' and
                                info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                            raise RuntimeError(f'Cannot safely package link/junction: {entry}')
                        name = source.name + '/' + relative
                        if stat.S_ISDIR(info.st_mode):
                            archive.mkdir(name + '/')
                            walk(entry)
                        elif stat.S_ISREG(info.st_mode):
                            archive.write(entry, name)
                            count += 1
                        else:
                            raise RuntimeError(f'Unsupported file type: {entry}')

                walk(source)
            with zipfile.ZipFile(temporary_zip) as archive:
                bad = archive.testzip()
                if bad:
                    raise RuntimeError(f'ZIP integrity check failed: {bad}')
            if force:
                os.replace(temporary_zip, output)
            elif os.name == 'nt':
                os.rename(temporary_zip, output)  # Windows refuses an existing destination.
            else:
                os.link(temporary_zip, output)
                os.unlink(temporary_zip)
            temporary_zip = None
        finally:
            if temporary_zip is not None:
                Path(temporary_zip).unlink(missing_ok=True)
    print(f'Created: {output}\nFiles: {count}; excluded entries: {excluded}\n'
          f'Archive root: {source.name}/')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='Source directory to package (required).')
    parser.add_argument('-o', '--output', type=Path,
                        help='Output name or path; relative to source parent. '
                             'Defaults to DIRECTORY.zip; .zip is appended if missing.')
    parser.add_argument('--force', action='store_true', help='Replace an existing ZIP.')
    args = parser.parse_args()
    try:
        pack(args.directory, force=args.force, output=args.output)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError,
            zipfile.BadZipFile) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
