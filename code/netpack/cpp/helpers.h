// Minimal, self-contained replacement for the former vendored fork of protoc's
// internal google/protobuf/compiler/cpp/helpers.{h,cc}.
//
// The old fork was a near-verbatim copy of protobuf ~3.19-era protoc INTERNALS
// (helpers.{h,cc}, names.h, options.h). It could never track system protobuf
// 35.x: helpers.cc even re-#included the *installed* internal header and
// implemented old-API functions against new declarations. It has been replaced
// by this header, which declares+implements ONLY the eight helpers that
// code/netpack/main.cpp actually uses, all built strictly on protobuf's PUBLIC
// descriptor API so it stays valid across protobuf versions.
//
// Everything here lives in namespace google::protobuf::compiler::cpp so that
// main.cpp's existing `cpp::` call sites and its `#include "cpp/helpers.h"`
// line remain untouched.
//
// Fidelity: every emitted string is intentionally byte-identical to what the
// fork produced for this project's protos, because those strings also feed the
// protocol version hash (main.cpp::HashProtocol -> FNV1a64). See the per-
// function comments for the fork source lines each behavior was extracted from.

#ifndef NETPACK_CPP_HELPERS_H__
#define NETPACK_CPP_HELPERS_H__

#include <string>
#include <vector>

#include "absl/container/flat_hash_set.h"
#include "absl/strings/ascii.h"
#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"

#include "google/protobuf/descriptor.h"
// descriptor.h only forward-declares MessageOptions; IsMapEntryMessage below calls
// options().map_entry(), which needs the complete type regardless of PCH ordering.
#include "google/protobuf/descriptor.pb.h"

namespace google
{
namespace protobuf
{
namespace compiler
{
namespace cpp
{

// --- C++ keyword set (fork: helpers.cc kKeywordList + Keywords()) -----------
// Used by ResolveKeyword / FieldName / EnumValueName to append a trailing '_'
// when a proto identifier collides with a C++ keyword. Copied verbatim from the
// fork's kKeywordList so mangling decisions are identical.
inline const absl::flat_hash_set<absl::string_view>& Keywords()
{
    static const auto* keywords = new absl::flat_hash_set<absl::string_view>{
        // clang-format off
        "NULL", "alignas", "alignof", "and", "and_eq", "asm", "assert", "auto",
        "bitand", "bitor", "bool", "break", "case", "catch", "char", "class",
        "compl", "const", "constexpr", "const_cast", "continue", "decltype",
        "default", "delete", "do", "double", "dynamic_cast", "else", "enum",
        "explicit", "export", "extern", "false", "float", "for", "friend",
        "goto", "if", "inline", "int", "long", "mutable", "namespace", "new",
        "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq",
        "private", "protected", "public", "register", "reinterpret_cast",
        "return", "short", "signed", "sizeof", "static", "static_assert",
        "static_cast", "struct", "switch", "template", "this", "thread_local",
        "throw", "true", "try", "typedef", "typeid", "typename", "union",
        "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while",
        "xor", "xor_eq", "char8_t", "char16_t", "char32_t", "concept",
        "consteval", "constinit", "co_await", "co_return", "co_yield",
        "requires",
        // clang-format on
    };
    return *keywords;
}

// fork: helpers.cc ResolveKeyword (lines 439-444).
inline std::string ResolveKeyword(absl::string_view name)
{
    if (Keywords().count(name) > 0)
    {
        return absl::StrCat(name, "_");
    }
    return std::string(name);
}

// IsMapEntryMessage -- fork: helpers.h lines 470-473 (unchanged public API).
inline bool IsMapEntryMessage(const Descriptor* descriptor)
{
    return descriptor->options().map_entry();
}

// ClassName(Descriptor) -- fork: helpers.cc lines 388-395.
// Joins nested types as Outer_Inner, appends "_DoNotUse" for map-entry types,
// and runs the result through ResolveKeyword. Port note: descriptor->name()
// returns absl::string_view in protobuf 35; absl::StrAppend accepts it directly.
inline std::string ClassName(const Descriptor* descriptor)
{
    const Descriptor* parent = descriptor->containing_type();
    std::string res;
    if (parent)
        absl::StrAppend(&res, ClassName(parent), "_");
    absl::StrAppend(&res, descriptor->name());
    if (IsMapEntryMessage(descriptor))
        absl::StrAppend(&res, "_DoNotUse");
    return ResolveKeyword(res);
}

// ClassName(EnumDescriptor) -- fork: helpers.cc lines 397-404.
inline std::string ClassName(const EnumDescriptor* enum_descriptor)
{
    if (enum_descriptor->containing_type() == nullptr)
    {
        return ResolveKeyword(enum_descriptor->name());
    }
    return absl::StrCat(ClassName(enum_descriptor->containing_type()), "_", enum_descriptor->name());
}

// FieldName -- fork: helpers.cc lines 531-538.
// Lower-cases the proto field name (proto1-compat) and keyword-mangles.
inline std::string FieldName(const FieldDescriptor* field)
{
    std::string result = std::string(field->name());
    absl::AsciiStrToLower(&result);
    if (Keywords().count(result) > 0)
    {
        result.append("_");
    }
    return result;
}

// EnumValueName -- fork: helpers.cc lines 565-571 (no lower-casing; keyword mangle only).
inline std::string EnumValueName(const EnumValueDescriptor* enum_value)
{
    std::string result = std::string(enum_value->name());
    if (Keywords().count(result) > 0)
    {
        result.append("_");
    }
    return result;
}

// PrimitiveTypeName -- fork: helpers.cc lines 662-691.
// CRITICAL: the returned strings are emitted verbatim into runtime-protobuf-free
// generated code AND feed the protocol hash, so the CppType->string mapping is
// copied byte-for-byte from the fork.
inline const char* PrimitiveTypeName(FieldDescriptor::CppType type)
{
    switch (type)
    {
    case FieldDescriptor::CPPTYPE_INT32: return "::int32_t";
    case FieldDescriptor::CPPTYPE_INT64: return "::int64_t";
    case FieldDescriptor::CPPTYPE_UINT32: return "::uint32_t";
    case FieldDescriptor::CPPTYPE_UINT64: return "::uint64_t";
    case FieldDescriptor::CPPTYPE_DOUBLE: return "double";
    case FieldDescriptor::CPPTYPE_FLOAT: return "float";
    case FieldDescriptor::CPPTYPE_BOOL: return "bool";
    case FieldDescriptor::CPPTYPE_ENUM: return "int";
    case FieldDescriptor::CPPTYPE_STRING: return "std::string";
    case FieldDescriptor::CPPTYPE_MESSAGE: return nullptr;
        // No default: let the compiler complain if a new CppType is added.
    }
    return nullptr;
}

// StripProto -- fork: helpers.cc lines 654-660 proxied to compiler::StripProto,
// which lives in libprotoc (the protoc compiler lib). NetPack links only the
// protobuf runtime, so that symbol is unavailable; StripProto's logic is
// trivial and version-stable, so it is inlined verbatim here (strip a trailing
// ".protodevel", else a trailing ".proto"; otherwise leave the name unchanged).
inline std::string StripProto(absl::string_view filename)
{
    if (absl::EndsWith(filename, ".protodevel"))
        filename.remove_suffix(sizeof(".protodevel") - 1);
    else if (absl::EndsWith(filename, ".proto"))
        filename.remove_suffix(sizeof(".proto") - 1);
    return std::string(filename);
}

// OneOfRange -- fork: helpers.h lines 1016-1052.
// Iterates a message's real (non-synthetic) oneofs via real_oneof_decl_count()/
// oneof_decl(). None of code/protocol/*.proto uses the proto3 `optional`
// keyword, so no synthetic oneofs exist and real_oneof_decl == oneof_decl here;
// using the real-oneof count preserves the fork's exact end() bound.
struct OneOfRangeImpl
{
    struct Iterator
    {
        using iterator_category = std::forward_iterator_tag;
        using value_type = const OneofDescriptor*;
        using difference_type = int;

        value_type operator*() { return descriptor->oneof_decl(idx); }

        friend bool operator==(const Iterator& a, const Iterator& b) { return a.idx == b.idx; }
        friend bool operator!=(const Iterator& a, const Iterator& b) { return !(a == b); }

        Iterator& operator++()
        {
            idx++;
            return *this;
        }

        int idx;
        const Descriptor* descriptor;
    };

    Iterator begin() const { return {0, descriptor}; }
    Iterator end() const { return {descriptor->real_oneof_decl_count(), descriptor}; }

    const Descriptor* descriptor;
};

inline OneOfRangeImpl OneOfRange(const Descriptor* desc)
{
    return {desc};
}

// FlattenMessagesInFile -- fork: helpers.cc lines 1329-1336, which used
// internal::cpp::VisitDescriptorsInFileOrder. That visitor is POST-ORDER: for
// each top-level message it recurses into every nested type first, then appends
// the message itself. Reimplemented here with the same post-order recursion so
// the emitted message ordering (and thus the hash) is identical.
inline void FlattenMessagesInFile(const Descriptor* descriptor, std::vector<const Descriptor*>* result)
{
    for (int i = 0; i < descriptor->nested_type_count(); i++)
        FlattenMessagesInFile(descriptor->nested_type(i), result);
    result->push_back(descriptor);
}

inline void FlattenMessagesInFile(const FileDescriptor* file, std::vector<const Descriptor*>* result)
{
    for (int i = 0; i < file->message_type_count(); i++)
        FlattenMessagesInFile(file->message_type(i), result);
}

} // namespace cpp
} // namespace compiler
} // namespace protobuf
} // namespace google

#endif // NETPACK_CPP_HELPERS_H__
