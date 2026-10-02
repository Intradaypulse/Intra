"""Reject APKs whose reflected WorkManager database constructor was stripped."""
import struct
import sys
import zipfile


def has_database_constructor(data):
    def u32(offset):
        return struct.unpack_from('<I', data, offset)[0]

    def u16(offset):
        return struct.unpack_from('<H', data, offset)[0]

    def uleb(offset):
        value = shift = 0
        while True:
            byte = data[offset]
            offset += 1
            value |= (byte & 127) << shift
            shift += 7
            if byte < 128:
                return value, offset

    strings = []
    for index in range(u32(56)):
        _, offset = uleb(u32(u32(60) + index * 4))
        strings.append(data[offset:data.index(0, offset)].decode('utf8', 'replace'))
    types = [strings[u32(u32(68) + index * 4)] for index in range(u32(64))]
    for index in range(u32(96)):
        class_offset = u32(100) + index * 32
        if types[u32(class_offset)] != 'Landroidx/work/impl/WorkDatabase_Impl;':
            continue
        offset = u32(class_offset + 24)
        counts = []
        for _ in range(4):
            count, offset = uleb(offset)
            counts.append(count)
        for _ in range(sum(counts[:2])):
            _, offset = uleb(offset)
            _, offset = uleb(offset)
        method_index = 0
        for _ in range(counts[2]):
            delta, offset = uleb(offset)
            method_index += delta
            access, offset = uleb(offset)
            _, offset = uleb(offset)
            method = u32(92) + method_index * 8
            proto = u32(76) + u16(method + 2) * 12
            params = u32(proto + 8)
            if strings[u32(method + 4)] == '<init>' and access & 1 and (not params or u32(params) == 0):
                return True
    return False


def main(apk):
    with zipfile.ZipFile(apk) as archive:
        if not any(has_database_constructor(archive.read(name))
                   for name in archive.namelist() if name.endswith('.dex')):
            raise SystemExit('Release startup unsafe: WorkDatabase_Impl public no-arg constructor missing')
    print('Verified WorkDatabase_Impl public no-arg constructor:', apk)


if __name__ == '__main__':
    main(sys.argv[1])
