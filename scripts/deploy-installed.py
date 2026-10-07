#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import sys

SCRIPT_OWNED_USER_UNITS = {
    'xdg-desktop-portal-singularity.service',
    'singularity-session.target',
    'singularity-polkit-agent.service',
}

SYSTEM_MIRRORS = {
    'polkit-1/actions': ['/usr/share/polkit-1/actions', '/etc/polkit-1/actions'],
    'dbus-1/system-services': ['/usr/share/dbus-1/system-services',
                               '/usr/local/share/dbus-1/system-services'],
    'dbus-1/system.d': ['/etc/dbus-1/system.d'],
    'accountsservice/interfaces': ['/usr/share/accountsservice/interfaces'],
}

SYSTEM_LIB_DIRS = {
    'lib/systemd/system': '/etc/systemd/system',
    'lib/systemd/user': '/etc/systemd/user',
    'lib/udev/rules.d': '/etc/udev/rules.d',
    'lib/modules-load.d': '/etc/modules-load.d',
}


def under(path, root):
    return path == root or path.startswith(root.rstrip('/') + '/')


def rest(path, root):
    return path[len(root.rstrip('/')) + 1:]


class Layout:
    def __init__(self, options, prefix, sysroot):
        self.build_prefix = options['prefix']
        self.prefix = prefix
        self.sysroot = sysroot

        def resolve(name):
            return os.path.normpath(os.path.join(self.build_prefix, options[name]))

        self.bindir = resolve('bindir')
        self.libexecdir = resolve('libexecdir')
        self.libdir = resolve('libdir')
        self.datadir = resolve('datadir')
        self.sysconfdir = resolve('sysconfdir')
        self.includedir = resolve('includedir')
        self.relocations = []
        for build_dir, deploy_dir in ((self.libexecdir, 'libexec'), (self.bindir, 'bin'),
                                      (self.libdir, 'lib'), (self.sysconfdir, 'etc'),
                                      (self.datadir, 'share'), (self.includedir, 'include')):
            if under(build_dir, self.build_prefix):
                target = os.path.join(prefix, deploy_dir)
                if build_dir != target:
                    self.relocations.append((build_dir, target))
        self.relocations.sort(key=lambda pair: -len(pair[0]))

    def system(self, path):
        return self.sysroot.rstrip('/') + path if self.sysroot else path

    def classify(self, dest):
        p = self.prefix
        if not under(dest, self.build_prefix):
            return 'system-file', self.system(dest), []
        if under(dest, self.libexecdir):
            return 'libexec', os.path.join(p, 'libexec', rest(dest, self.libexecdir)), []
        if under(dest, self.bindir):
            return 'bin', os.path.join(p, 'bin', rest(dest, self.bindir)), []
        plugins = os.path.join(self.libdir, 'singularity', 'plugins')
        if under(dest, plugins):
            return 'plugin', os.path.join(p, 'share', 'singularity', 'plugins', rest(dest, plugins)), []
        if under(dest, self.libdir):
            return 'lib', os.path.join(p, 'lib', rest(dest, self.libdir)), []
        rel = rest(dest, self.build_prefix)
        for lib_rel, system_dir in SYSTEM_LIB_DIRS.items():
            if under(rel, lib_rel):
                name = rest(rel, lib_rel)
                if lib_rel == 'lib/systemd/user' and name in SCRIPT_OWNED_USER_UNITS:
                    return 'script-owned', os.path.join(p, rel), []
                return 'system-config', self.system(os.path.join(system_dir, name)), []
        if under(dest, self.datadir):
            sub = rest(dest, self.datadir)
            for mirror_rel, system_dirs in SYSTEM_MIRRORS.items():
                if under(sub, mirror_rel):
                    name = rest(sub, mirror_rel)
                    return 'mirrored', os.path.join(p, 'share', sub), [
                        self.system(os.path.join(d, name)) for d in system_dirs]
            if under(sub, 'dbus-1/services'):
                return 'dbus-service', os.path.join(p, 'share', sub), []
            return 'data', os.path.join(p, 'share', sub), []
        if under(dest, self.sysconfdir):
            sub = rest(dest, self.sysconfdir)
            if under(sub, 'xdg/autostart'):
                return 'autostart', os.path.join(p, 'etc', sub), []
            return 'config', os.path.join(p, 'etc', sub), []
        if under(dest, self.includedir):
            return 'data', os.path.join(p, 'include', rest(dest, self.includedir)), []
        return 'data', os.path.join(p, rel), []

    def relocate(self, text):
        for build_dir, target in self.relocations:
            text = re.sub(re.escape(build_dir) + r'(?=[/\s"\'<:;,]|$)', target, text, flags=re.M)
        return text


def read_text(path):
    if os.path.islink(path) or not os.path.isfile(path) or os.access(path, os.X_OK):
        return None
    with open(path, 'rb') as handle:
        data = handle.read()
    if b'\0' in data[:8192]:
        return None
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return None


def owning_app(src):
    parts = src.split('/subprojects/', 1)
    if len(parts) != 2:
        return None
    return parts[1].split('/', 1)[0]


class Installer:
    def __init__(self, layout, dry_run):
        self.layout = layout
        self.dry_run = dry_run
        self.counts = {}
        self.notices = []
        self.missing = []
        self.dbus_services = []
        self.executables = set()

    def atomic_write(self, dest, text, mode):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + '.new'
        with open(tmp, 'w', encoding='utf-8') as handle:
            handle.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, dest)

    def atomic_copy(self, src, dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + '.new'
        if os.path.lexists(tmp):
            os.unlink(tmp)
        shutil.copy2(src, tmp)
        os.replace(tmp, dest)

    def atomic_link(self, target, dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + '.new'
        if os.path.lexists(tmp):
            os.unlink(tmp)
        os.symlink(target, tmp)
        if os.path.isdir(dest) and not os.path.islink(dest):
            shutil.rmtree(dest)
        os.replace(tmp, dest)

    def content(self, kind, src):
        text = read_text(src)
        if text is None:
            return None
        text = self.layout.relocate(text)
        if kind in ('dbus-service', 'autostart'):
            bindir = os.path.join(self.layout.prefix, 'bin')
            text = re.sub(r'^Exec=([a-z][^/\s]*)', lambda m: 'Exec=%s/%s' % (bindir, m.group(1)), text, flags=re.M)
        return text

    def put(self, kind, src, dest):
        if os.path.islink(src) or not os.path.isabs(src):
            self.atomic_link(os.readlink(src) if os.path.islink(src) else src, dest)
            return
        if os.path.isdir(src):
            for root, dirs, files in os.walk(src):
                for name in files:
                    path = os.path.join(root, name)
                    self.put(kind, path, os.path.join(dest, os.path.relpath(path, src)))
            return
        text = self.content(kind, src)
        if text is None:
            self.atomic_copy(src, dest)
        else:
            self.atomic_write(dest, text, os.stat(src).st_mode & 0o7777)

    def writable_dir(self, path):
        try:
            os.makedirs(path, exist_ok=True)
        except OSError:
            return False
        return os.access(path, os.W_OK)

    def install(self, kind, src, dest, mirrors):
        if os.path.isabs(src) and not os.path.lexists(src):
            self.missing.append(src)
            return
        self.counts[kind] = self.counts.get(kind, 0) + 1
        if kind == 'dbus-service':
            self.dbus_services.append(os.path.basename(dest))
        if kind == 'libexec' and os.path.dirname(dest) == os.path.join(self.layout.prefix, 'libexec'):
            self.executables.add(os.path.basename(dest))
        if self.dry_run:
            print('  %-14s %s -> %s' % (kind, src, dest))
            for mirror in mirrors:
                print('  %-14s   also -> %s (when writable)' % ('', mirror))
            return
        if kind == 'script-owned':
            return
        if kind == 'system-file':
            self.install_system_file(src, dest)
            return
        if kind == 'system-config':
            if self.writable_dir(os.path.dirname(dest)):
                self.put(kind, src, dest)
            else:
                self.notices.append('%s not installed (%s is read-only)' % (dest, os.path.dirname(dest)))
            return
        self.put(kind, src, dest)
        for mirror in mirrors:
            if self.writable_dir(os.path.dirname(mirror)):
                try:
                    self.put(kind, src, mirror)
                    self.notices.append(mirror)
                    break
                except OSError:
                    pass
        else:
            if mirrors:
                self.notices.append('%s not mirrored to %s (read-only); ship it via the OS image'
                                    % (os.path.basename(dest), ' or '.join(os.path.dirname(m) for m in mirrors)))

    def install_system_file(self, src, dest):
        text = self.content('system-file', src)
        keep_local_edits = under(dest, self.layout.system('/etc'))
        if os.path.exists(dest) and keep_local_edits:
            with open(dest, 'rb') as handle:
                current = handle.read()
            wanted = text.encode('utf-8') if text is not None else open(src, 'rb').read()
            if current != wanted:
                self.notices.append('%s differs from the build and was left untouched' % dest)
            return
        if not self.writable_dir(os.path.dirname(dest)):
            self.notices.append('%s not installed (%s is read-only)' % (dest, os.path.dirname(dest)))
            return
        self.put('system-file', src, dest)
        self.notices.append(dest)

    def link_libexec(self, bin_names):
        bindir = os.path.join(self.layout.prefix, 'bin')
        for name in sorted(self.executables - bin_names):
            dest = os.path.join(bindir, name)
            if self.dry_run:
                print('  %-14s %s -> ../libexec/%s' % ('bin-link', dest, name))
            else:
                self.atomic_link(os.path.join('..', 'libexec', name), dest)
            self.counts['bin-link'] = self.counts.get('bin-link', 0) + 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--info', required=True)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--sysroot', default='')
    parser.add_argument('--skip', default='')
    parser.add_argument('--dbus-list')
    parser.add_argument('--manifest')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    try:
        with open(os.path.join(args.info, 'intro-installed.json')) as handle:
            installed = json.load(handle)
        with open(os.path.join(args.info, 'intro-buildoptions.json')) as handle:
            options = {o['name']: o['value'] for o in json.load(handle)}
    except (OSError, ValueError) as error:
        sys.stderr.write('  no meson install data in %s: %s\n' % (args.info, error))
        return 1

    layout = Layout(options, args.prefix, args.sysroot)
    installer = Installer(layout, args.dry_run)
    skipped = set(args.skip.split())
    manifest = []
    bin_names = set()
    skipped_count = 0
    for src, dest in sorted(installed.items(), key=lambda item: item[1]):
        if owning_app(src) in skipped:
            skipped_count += 1
            continue
        kind, target, mirrors = layout.classify(dest)
        if kind == 'bin':
            bin_names.add(os.path.basename(target))
        manifest.append((kind, src, dest, target, mirrors))

    if layout.build_prefix != args.prefix:
        print('  note: the build prefix is %s, the deploy prefix is %s; paths compiled into the '
              'binaries still point at %s (reconfigure with --prefix=%s --libdir=lib to match)'
              % (layout.build_prefix, args.prefix, layout.build_prefix, args.prefix))
    for kind, src, dest, target, mirrors in manifest:
        installer.install(kind, src, target, mirrors)
    installer.link_libexec(bin_names)

    if args.manifest:
        with open(args.manifest, 'w') as handle:
            for kind, src, dest, target, mirrors in manifest:
                handle.write('%s\t%s\t%s\t%s\n' % (kind, src, dest, target))
    if args.dbus_list:
        with open(args.dbus_list, 'w') as handle:
            handle.write(''.join(name + '\n' for name in installer.dbus_services))

    summary = ', '.join('%d %s' % (count, kind) for kind, count in sorted(installer.counts.items()))
    print('  %d files from the build (%s)' % (sum(installer.counts.values()), summary))
    if skipped_count:
        print('  %d files of apps outside APPS=%s skipped' % (skipped_count, os.environ.get('APPS', 'all')))
    for notice in installer.notices:
        print('  ' + notice)
    for src in installer.missing:
        print('  WARNING: not built, skipped: %s' % src, file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
