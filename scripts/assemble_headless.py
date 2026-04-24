#!/usr/bin/env python3
"""
assemble_headless.py
====================
Non-GUI port of the course-provided assembler.py.  Identical algorithm and
output, but reads paths from argv instead of using tkinter file dialogs.

Usage:
    python3 assemble_headless.py <source.txt> <data.coe> <text.coe>

The file format and bit layout match assembler.py exactly (verified against
helloworld_py.txt -> 11 instructions for the GRISC ASIP).
"""
import sys
import os


def dec2bin(num, digits):
    return bin(num)[2:].zfill(digits)


def build_dicts():
    ops = {
        'add': '00000', 'sub': '00001',
        'sll': '00010', 'srl': '00011', 'sra': '00100',
        'and': '00101', 'or':  '00110', 'xor': '00111',
        'slt': '01000', 'sgt': '01001', 'seq': '01010',
        'send': '01011', 'recv': '01100',
        'jr':  '01101', 'wpix': '01110', 'rpix': '01111',
        'beq': '10000', 'bne': '10001', 'ori': '10010',
        'lw':  '10011', 'sw':  '10100',
        'j':   '11000', 'jal': '11001', 'clrscr': '11010',
        'la':  '10010',
    }
    types = {'00': 'r', '01': 'r', '10': 'i', '11': 'j'}
    regs = {'$zero': '00000', '$pc': '00001', '$ra': '00010'}
    for i in range(3, 32):
        regs[f'$r{i}'] = dec2bin(i, 5)
    return ops, types, regs


def data_labels(data_lines):
    labels = {}
    counter = 0
    for line in data_lines:
        tag, rest = line.split(':', 1)
        typ = rest.split()[0]
        val = rest.split(typ, 1)[1].strip()
        if typ == 'str':
            val = val.split('"')[1]
        labels[tag] = dec2bin(counter, 16)
        if typ == 'str':
            counter += len(val) + 1
        else:
            counter += 1
    return labels


def build_data_coe(data_lines):
    out = ['MEMORY_INITIALIZATION_RADIX=2;', 'MEMORY_INITIALIZATION_VECTOR=']
    for idx, line in enumerate(data_lines):
        tag, rest = line.split(':', 1)
        typ = rest.split()[0]
        val = rest.split(typ, 1)[1].strip()
        last = idx == len(data_lines) - 1

        if typ == 'str':
            val = val.split('"')[1]
            for ch in val:
                out.append(dec2bin(ord(ch), 16) + ',')
            out.append(dec2bin(0, 16) + (';' if last else ','))
        else:
            out.append(dec2bin(int(val), 16) + (';' if last else ','))
    return out


def text_labels(text_lines):
    new_lines, labels, counter = [], {}, 0
    for line in text_lines:
        if ':' in line:
            tag = line.split(':')[0]
            labels[tag] = dec2bin(counter, 16)
        else:
            new_lines.append(line)
            counter += 1
    return labels, new_lines


def build_text_coe(text_lines, d_labels, t_labels):
    ops, types, regs = build_dicts()
    out = ['MEMORY_INITIALIZATION_RADIX=2;', 'MEMORY_INITIALIZATION_VECTOR=']

    for idx, line in enumerate(text_lines):
        args = line.strip().split()
        op = args[0]
        binop = ops[op]
        optype = types[binop[0:2]]
        cmd = binop

        if optype == 'r':
            for j in range(1, len(args)):
                cmd += regs[args[j]]
        elif optype == 'i':
            if op == 'la':
                cmd += regs[args[1]] + regs['$zero'] + d_labels[args[2]]
            elif op in ('lw', 'sw'):
                cmd += regs[args[1]] + regs[args[2]] + d_labels[args[3]]
            elif op in ('beq', 'bne'):
                cmd += regs[args[1]] + regs[args[2]] + t_labels[args[3]]
            else:
                cmd += regs[args[1]] + regs[args[2]] + dec2bin(int(args[3]), 16)
        else:
            if op in ('j', 'jal'):
                cmd += t_labels[args[1]]

        cmd = cmd.ljust(32, '0')
        last = idx == len(text_lines) - 1
        out.append(cmd + (';' if last else ','))
    return out


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    src_path, data_path, text_path = sys.argv[1:4]

    with open(src_path, 'r') as f:
        cleaned = []
        for line in f:
            stripped = line.strip().split('//')[0].strip()
            if stripped:
                cleaned.append(stripped)

    d_start = cleaned.index('.data') + 1
    t_start = cleaned.index('.text') + 1
    data_lines = cleaned[d_start:t_start - 1]
    text_lines_raw = cleaned[t_start:]

    d_labels = data_labels(data_lines)
    t_labels, text_lines = text_labels(text_lines_raw)
    data_out = build_data_coe(data_lines)
    text_out = build_text_coe(text_lines, d_labels, t_labels)

    os.makedirs(os.path.dirname(os.path.abspath(data_path)), exist_ok=True)
    with open(data_path, 'w') as f:
        f.write('\n'.join(data_out) + '\n')
    with open(text_path, 'w') as f:
        f.write('\n'.join(text_out) + '\n')

    print(f"Source       : {src_path}")
    print(f"Data labels  : {d_labels}")
    print(f"Text labels  : {t_labels}")
    print(f"Wrote {len(data_out) - 2} data words to   {data_path}")
    print(f"Wrote {len(text_out) - 2} text words to   {text_path}")


if __name__ == '__main__':
    main()
