package main

import (
	"debug/macho"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"unicode"
)

type descriptor struct {
	Offset     uint64   `json:"offset"`
	TypeRefHex string   `json:"typeRefHex"`
	TypeHint   string   `json:"typeHint,omitempty"`
	Kind       uint16   `json:"kind"`
	Fields     []string `json:"fields"`
}

type image struct {
	file     *macho.File
	sections []*macho.Section
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: swift-fieldmd <Mach-O>")
		os.Exit(2)
	}
	img, closeImage, err := openImage(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer closeImage()

	fieldmd := img.section("__swift5_fieldmd")
	if fieldmd == nil {
		panic("__swift5_fieldmd not found")
	}
	data, err := fieldmd.Data()
	if err != nil {
		panic(err)
	}
	typeNames := img.typeNamesByFieldDescriptor()

	var result []descriptor
	for cursor := uint64(0); cursor+16 <= uint64(len(data)); {
		recordSize := binary.LittleEndian.Uint16(data[cursor+10 : cursor+12])
		count := binary.LittleEndian.Uint32(data[cursor+12 : cursor+16])
		if recordSize < 12 || count > 10000 {
			break
		}
		total := uint64(16) + uint64(recordSize)*uint64(count)
		if cursor+total > uint64(len(data)) {
			break
		}

		descriptorVM := fieldmd.Addr + cursor
		typeTarget := addRelative(descriptorVM, data[cursor:cursor+4])
		typeBytes := img.cString(typeTarget, 256)
		d := descriptor{
			Offset:     cursor,
			TypeRefHex: hex.EncodeToString(typeBytes),
			TypeHint:   printableHint(typeBytes),
			Kind:       binary.LittleEndian.Uint16(data[cursor+8 : cursor+10]),
		}
		if name := typeNames[descriptorVM]; name != "" {
			d.TypeHint = name
		}
		for index := uint32(0); index < count; index++ {
			record := cursor + 16 + uint64(index)*uint64(recordSize)
			nameFieldVM := fieldmd.Addr + record + 8
			nameTarget := addRelative(nameFieldVM, data[record+8:record+12])
			name := string(img.cString(nameTarget, 512))
			if name == "" {
				name = fmt.Sprintf("<field-%d>", index)
			}
			d.Fields = append(d.Fields, name)
		}
		result = append(result, d)
		cursor += total
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(result); err != nil {
		panic(err)
	}
}

func openImage(path string) (*image, func(), error) {
	if fat, err := macho.OpenFat(path); err == nil {
		for _, arch := range fat.Arches {
			if arch.Cpu == macho.CpuArm64 {
				return &image{file: arch.File, sections: arch.Sections}, func() { _ = fat.Close() }, nil
			}
		}
		_ = fat.Close()
	}
	file, err := macho.Open(path)
	if err != nil {
		return nil, func() {}, err
	}
	return &image{file: file, sections: file.Sections}, func() { _ = file.Close() }, nil
}

func (i *image) section(name string) *macho.Section {
	for _, section := range i.sections {
		if section.Name == name {
			return section
		}
	}
	return nil
}

func (i *image) cString(address uint64, limit int) []byte {
	for _, section := range i.sections {
		if address < section.Addr || address >= section.Addr+section.Size {
			continue
		}
		data, err := section.Data()
		if err != nil {
			return nil
		}
		start := address - section.Addr
		end := start
		for end < uint64(len(data)) && int(end-start) < limit && data[end] != 0 {
			end++
		}
		return data[start:end]
	}
	return nil
}

func (i *image) bytesAt(address uint64, count uint64) []byte {
	for _, section := range i.sections {
		if address < section.Addr || address+count > section.Addr+section.Size {
			continue
		}
		data, err := section.Data()
		if err != nil {
			return nil
		}
		start := address - section.Addr
		return data[start : start+count]
	}
	return nil
}

// __swift5_types points at nominal type descriptors. Every type descriptor starts with
// the same five words: flags, parent, name, access function and field descriptor. Mapping
// that final relative pointer back to __swift5_fieldmd gives each recovered field list the
// Swift type name it belongs to, rather than relying on nearby strings.
func (i *image) typeNamesByFieldDescriptor() map[uint64]string {
	result := map[uint64]string{}
	types := i.section("__swift5_types")
	if types == nil {
		return result
	}
	data, err := types.Data()
	if err != nil {
		return result
	}
	for cursor := uint64(0); cursor+4 <= uint64(len(data)); cursor += 4 {
		entryVM := types.Addr + cursor
		descriptorVM := addRelative(entryVM, data[cursor:cursor+4])
		header := i.bytesAt(descriptorVM, 20)
		if len(header) != 20 {
			continue
		}
		nameVM := addRelative(descriptorVM+8, header[8:12])
		fieldVM := addRelative(descriptorVM+16, header[16:20])
		name := string(i.cString(nameVM, 256))
		if name == "" || fieldVM == descriptorVM+16 {
			continue
		}
		result[fieldVM] = name
	}
	return result
}

func addRelative(base uint64, bytes []byte) uint64 {
	return uint64(int64(base) + int64(int32(binary.LittleEndian.Uint32(bytes))))
}

func printableHint(value []byte) string {
	var result []rune
	for _, b := range value {
		r := rune(b)
		if unicode.IsPrint(r) && r < 128 {
			result = append(result, r)
		}
	}
	return string(result)
}
