using System.Buffers;
using System.Text.Json;

namespace Plain.Engine;

/// <summary>
/// Writing JSON without reflection.
///
/// The engine is compiled ahead of time, which means there is no reflection at run time to look at a type and work
/// out how to write it. Serializing an object by handing it to a serializer therefore does not work here, and
/// finding that out is a crash on the first call rather than a warning at build time.
///
/// So the answers are written out a field at a time. It is more typing and it is worth it: escaping is handled by
/// the writer that knows the rules, and what crosses the boundary is exactly what this file says, which is easier
/// to check against what the Swift side expects.
/// </summary>
internal sealed class Json : IDisposable
{
    private readonly ArrayBufferWriter<byte> _buffer = new();
    private readonly Utf8JsonWriter _writer;

    public Json() => _writer = new Utf8JsonWriter(_buffer, new JsonWriterOptions { Indented = false });

    public Json Object(Action<Json> inside)
    {
        _writer.WriteStartObject();
        inside(this);
        _writer.WriteEndObject();
        return this;
    }

    public Json Object(string name, Action<Json> inside)
    {
        _writer.WritePropertyName(name);
        _writer.WriteStartObject();
        inside(this);
        _writer.WriteEndObject();
        return this;
    }

    public Json Array<T>(string name, IEnumerable<T> items, Action<Json, T> each)
    {
        _writer.WritePropertyName(name);
        _writer.WriteStartArray();
        foreach (var item in items)
        {
            _writer.WriteStartObject();
            each(this, item);
            _writer.WriteEndObject();
        }
        _writer.WriteEndArray();
        return this;
    }

    public Json Strings(string name, IEnumerable<string> items)
    {
        _writer.WritePropertyName(name);
        _writer.WriteStartArray();
        foreach (var item in items) _writer.WriteStringValue(item);
        _writer.WriteEndArray();
        return this;
    }

    public Json Put(string name, string? value)
    {
        if (value is null) _writer.WriteNull(name); else _writer.WriteString(name, value);
        return this;
    }

    public Json Put(string name, int value) { _writer.WriteNumber(name, value); return this; }
    public Json Put(string name, long value) { _writer.WriteNumber(name, value); return this; }
    public Json Put(string name, double value) { _writer.WriteNumber(name, value); return this; }
    public Json Put(string name, bool value) { _writer.WriteBoolean(name, value); return this; }

    public string Text()
    {
        _writer.Flush();
        return System.Text.Encoding.UTF8.GetString(_buffer.WrittenSpan);
    }

    public void Dispose() => _writer.Dispose();

    /// <summary>The usual shape: one object, written and handed back as a string.</summary>
    public static string Write(Action<Json> inside)
    {
        using var json = new Json();
        json.Object(inside);
        return json.Text();
    }
}
