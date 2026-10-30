import Foundation

/// A small catalog of the .NET classes programs use most, with VB.NET signatures. It gives VB.NET IntelliSense
/// (which has no language server) member lists, and fills the Object Browser's ".NET" section.
public struct DotNetMember: Sendable, Equatable {
    public let name: String
    public let isShared: Bool
    public let isMethod: Bool
    /// VB.NET form: `WriteLine(value As String)` or `Length As Integer`.
    public let signature: String
    public let returnType: String?
}

public struct DotNetType: Sendable, Equatable {
    public let name: String
    public let namespace: String
    public let kind: CodeSymbol.Kind
    public let members: [DotNetMember]

    public var qualifiedName: String { namespace + "." + name }
}

public enum DotNetCatalog {
    /// Entries: `+` marks Shared members, `.` marks properties; a member without `(` is a property or field.
    private static let source: [(String, String, CodeSymbol.Kind, String)] = [
        ("System", "Console", .class, "+WriteLine(value As String) | +Write(value As String) | +ReadLine() As String | +ReadKey() As ConsoleKeyInfo | +Clear() | +Beep() | +ResetColor() | +SetCursorPosition(left As Integer, top As Integer) | +.ForegroundColor As ConsoleColor | +.BackgroundColor As ConsoleColor | +.Title As String | +.CursorLeft As Integer | +.CursorTop As Integer | +.KeyAvailable As Boolean | +.WindowWidth As Integer | +.Out As TextWriter | +.Error As TextWriter"),
        ("System", "String", .class, "Length As Integer | ToUpper() As String | ToLower() As String | Trim() As String | TrimStart() As String | TrimEnd() As String | Substring(startIndex As Integer, length As Integer) As String | Replace(oldValue As String, newValue As String) As String | Split(separator As Char) As String() | Contains(value As String) As Boolean | StartsWith(value As String) As Boolean | EndsWith(value As String) As Boolean | IndexOf(value As String) As Integer | LastIndexOf(value As String) As Integer | PadLeft(totalWidth As Integer) As String | PadRight(totalWidth As Integer) As String | Insert(startIndex As Integer, value As String) As String | Remove(startIndex As Integer) As String | ToCharArray() As Char() | CompareTo(value As String) As Integer | Chars(index As Integer) As Char | +Format(format As String, ParamArray args As Object()) As String | +Join(separator As String, values As IEnumerable(Of String)) As String | +Concat(ParamArray values As String()) As String | +IsNullOrEmpty(value As String) As Boolean | +IsNullOrWhiteSpace(value As String) As Boolean | +Compare(strA As String, strB As String) As Integer | +.Empty As String"),
        ("System", "Math", .class, "+Abs(value As Double) As Double | +Max(val1 As Double, val2 As Double) As Double | +Min(val1 As Double, val2 As Double) As Double | +Pow(x As Double, y As Double) As Double | +Sqrt(d As Double) As Double | +Round(value As Double, digits As Integer) As Double | +Floor(d As Double) As Double | +Ceiling(d As Double) As Double | +Truncate(d As Double) As Double | +Sign(value As Double) As Integer | +Clamp(value As Double, min As Double, max As Double) As Double | +Sin(a As Double) As Double | +Cos(d As Double) As Double | +Tan(a As Double) As Double | +Log(d As Double) As Double | +Log10(d As Double) As Double | +Exp(d As Double) As Double | +.PI As Double | +.E As Double"),
        ("System", "DateTime", .structure, "+.Now As DateTime | +.Today As DateTime | +.UtcNow As DateTime | +Parse(s As String) As DateTime | +TryParse(s As String, ByRef result As DateTime) As Boolean | +DaysInMonth(year As Integer, month As Integer) As Integer | +IsLeapYear(year As Integer) As Boolean | AddDays(value As Double) As DateTime | AddHours(value As Double) As DateTime | AddMinutes(value As Double) As DateTime | AddSeconds(value As Double) As DateTime | AddMonths(months As Integer) As DateTime | AddYears(value As Integer) As DateTime | Subtract(value As DateTime) As TimeSpan | ToShortDateString() As String | ToLongDateString() As String | ToShortTimeString() As String | Year As Integer | Month As Integer | Day As Integer | Hour As Integer | Minute As Integer | Second As Integer | Millisecond As Integer | DayOfWeek As DayOfWeek | DayOfYear As Integer | Date As DateTime | TimeOfDay As TimeSpan"),
        ("System", "TimeSpan", .structure, "+FromSeconds(value As Double) As TimeSpan | +FromMinutes(value As Double) As TimeSpan | +FromHours(value As Double) As TimeSpan | +FromDays(value As Double) As TimeSpan | +FromMilliseconds(value As Double) As TimeSpan | +.Zero As TimeSpan | Days As Integer | Hours As Integer | Minutes As Integer | Seconds As Integer | Milliseconds As Integer | TotalDays As Double | TotalHours As Double | TotalMinutes As Double | TotalSeconds As Double | TotalMilliseconds As Double | Add(ts As TimeSpan) As TimeSpan"),
        ("System", "Int32", .structure, "+Parse(s As String) As Integer | +TryParse(s As String, ByRef result As Integer) As Boolean | +.MaxValue As Integer | +.MinValue As Integer | CompareTo(value As Integer) As Integer"),
        ("System", "Int64", .structure, "+Parse(s As String) As Long | +TryParse(s As String, ByRef result As Long) As Boolean | +.MaxValue As Long | +.MinValue As Long"),
        ("System", "Double", .structure, "+Parse(s As String) As Double | +TryParse(s As String, ByRef result As Double) As Boolean | +IsNaN(d As Double) As Boolean | +IsInfinity(d As Double) As Boolean | +.MaxValue As Double | +.MinValue As Double | +.NaN As Double | +.Epsilon As Double"),
        ("System", "Decimal", .structure, "+Parse(s As String) As Decimal | +TryParse(s As String, ByRef result As Decimal) As Boolean | +Round(d As Decimal, decimals As Integer) As Decimal | +.MaxValue As Decimal | +.Zero As Decimal"),
        ("System", "Boolean", .structure, "+Parse(value As String) As Boolean | +TryParse(value As String, ByRef result As Boolean) As Boolean | +.TrueString As String | +.FalseString As String"),
        ("System", "Char", .structure, "+IsDigit(c As Char) As Boolean | +IsLetter(c As Char) As Boolean | +IsLetterOrDigit(c As Char) As Boolean | +IsWhiteSpace(c As Char) As Boolean | +IsUpper(c As Char) As Boolean | +IsLower(c As Char) As Boolean | +IsPunctuation(c As Char) As Boolean | +ToUpper(c As Char) As Char | +ToLower(c As Char) As Char"),
        ("System", "Convert", .class, "+ToInt32(value As Object) As Integer | +ToInt64(value As Object) As Long | +ToDouble(value As Object) As Double | +ToDecimal(value As Object) As Decimal | +ToString(value As Object) As String | +ToBoolean(value As Object) As Boolean | +ToDateTime(value As Object) As DateTime | +ToChar(value As Object) As Char | +ToBase64String(inArray As Byte()) As String | +FromBase64String(s As String) As Byte()"),
        ("System", "Random", .class, "Next() As Integer | Next(maxValue As Integer) As Integer | Next(minValue As Integer, maxValue As Integer) As Integer | NextDouble() As Double | NextBytes(buffer As Byte()) | +.Shared As Random"),
        ("System", "Guid", .structure, "+NewGuid() As Guid | +Parse(input As String) As Guid | +TryParse(input As String, ByRef result As Guid) As Boolean | +.Empty As Guid"),
        ("System", "Environment", .class, "+.NewLine As String | +.CurrentDirectory As String | +.MachineName As String | +.UserName As String | +.OSVersion As OperatingSystem | +.ProcessorCount As Integer | +.TickCount As Integer | +.Version As Version | +Exit(exitCode As Integer) | +GetEnvironmentVariable(variable As String) As String | +GetCommandLineArgs() As String() | +GetFolderPath(folder As SpecialFolder) As String"),
        ("System", "Array", .class, "Length As Integer | Rank As Integer | GetValue(index As Integer) As Object | SetValue(value As Object, index As Integer) | +Sort(array As Array) | +Reverse(array As Array) | +IndexOf(array As Array, value As Object) As Integer | +Resize(ByRef array As T(), newSize As Integer) | +Copy(sourceArray As Array, destinationArray As Array, length As Integer) | +Clear(array As Array) | +Empty() As T() | +Exists(array As T(), match As Predicate(Of T)) As Boolean | +Find(array As T(), match As Predicate(Of T)) As T"),
        ("System", "Exception", .class, "Message As String | StackTrace As String | InnerException As Exception | Source As String | Data As IDictionary | HResult As Integer | GetBaseException() As Exception"),
        ("System", "Object", .class, "ToString() As String | Equals(obj As Object) As Boolean | GetHashCode() As Integer | GetType() As Type"),
        ("System.Collections.Generic", "List", .class, "Add(item As T) | AddRange(collection As IEnumerable(Of T)) | Remove(item As T) As Boolean | RemoveAt(index As Integer) | RemoveAll(match As Predicate(Of T)) As Integer | Clear() | Contains(item As T) As Boolean | IndexOf(item As T) As Integer | Insert(index As Integer, item As T) | Sort() | Reverse() | ToArray() As T() | Find(match As Predicate(Of T)) As T | FindAll(match As Predicate(Of T)) As List(Of T) | FindIndex(match As Predicate(Of T)) As Integer | ForEach(action As Action(Of T)) | Exists(match As Predicate(Of T)) As Boolean | Count As Integer | Capacity As Integer | Item(index As Integer) As T"),
        ("System.Collections.Generic", "Dictionary", .class, "Add(key As TKey, value As TValue) | Remove(key As TKey) As Boolean | ContainsKey(key As TKey) As Boolean | ContainsValue(value As TValue) As Boolean | TryGetValue(key As TKey, ByRef value As TValue) As Boolean | TryAdd(key As TKey, value As TValue) As Boolean | Clear() | Count As Integer | Keys As KeyCollection | Values As ValueCollection | Item(key As TKey) As TValue"),
        ("System.Collections.Generic", "HashSet", .class, "Add(item As T) As Boolean | Remove(item As T) As Boolean | Contains(item As T) As Boolean | Clear() | UnionWith(other As IEnumerable(Of T)) | IntersectWith(other As IEnumerable(Of T)) | ExceptWith(other As IEnumerable(Of T)) | Count As Integer"),
        ("System.Collections.Generic", "Queue", .class, "Enqueue(item As T) | Dequeue() As T | Peek() As T | TryDequeue(ByRef result As T) As Boolean | Contains(item As T) As Boolean | Clear() | Count As Integer"),
        ("System.Collections.Generic", "Stack", .class, "Push(item As T) | Pop() As T | Peek() As T | TryPop(ByRef result As T) As Boolean | Contains(item As T) As Boolean | Clear() | Count As Integer"),
        ("System.Text", "StringBuilder", .class, "Append(value As String) As StringBuilder | AppendLine(value As String) As StringBuilder | AppendFormat(format As String, ParamArray args As Object()) As StringBuilder | Insert(index As Integer, value As String) As StringBuilder | Remove(startIndex As Integer, length As Integer) As StringBuilder | Replace(oldValue As String, newValue As String) As StringBuilder | Clear() As StringBuilder | ToString() As String | Length As Integer | Capacity As Integer"),
        ("System.Text", "Encoding", .class, "+.UTF8 As Encoding | +.ASCII As Encoding | +.Unicode As Encoding | GetBytes(s As String) As Byte() | GetString(bytes As Byte()) As String"),
        ("System.IO", "File", .class, "+ReadAllText(path As String) As String | +WriteAllText(path As String, contents As String) | +AppendAllText(path As String, contents As String) | +ReadAllLines(path As String) As String() | +WriteAllLines(path As String, contents As String()) | +ReadAllBytes(path As String) As Byte() | +WriteAllBytes(path As String, bytes As Byte()) | +Exists(path As String) As Boolean | +Delete(path As String) | +Copy(sourceFileName As String, destFileName As String) | +Move(sourceFileName As String, destFileName As String) | +ReadLines(path As String) As IEnumerable(Of String) | +OpenText(path As String) As StreamReader | +CreateText(path As String) As StreamWriter | +GetLastWriteTime(path As String) As DateTime"),
        ("System.IO", "Directory", .class, "+Exists(path As String) As Boolean | +CreateDirectory(path As String) As DirectoryInfo | +Delete(path As String, recursive As Boolean) | +GetFiles(path As String) As String() | +GetDirectories(path As String) As String() | +EnumerateFiles(path As String) As IEnumerable(Of String) | +GetCurrentDirectory() As String | +SetCurrentDirectory(path As String) | +Move(sourceDirName As String, destDirName As String)"),
        ("System.IO", "Path", .class, "+Combine(ParamArray paths As String()) As String | +GetFileName(path As String) As String | +GetFileNameWithoutExtension(path As String) As String | +GetExtension(path As String) As String | +GetDirectoryName(path As String) As String | +GetFullPath(path As String) As String | +GetTempPath() As String | +GetTempFileName() As String | +ChangeExtension(path As String, extension As String) As String | +.DirectorySeparatorChar As Char"),
        ("System.IO", "StreamReader", .class, "ReadLine() As String | ReadToEnd() As String | Read() As Integer | Peek() As Integer | Close() | Dispose() | EndOfStream As Boolean"),
        ("System.IO", "StreamWriter", .class, "Write(value As String) | WriteLine(value As String) | Flush() | Close() | Dispose() | AutoFlush As Boolean"),
        ("System.Threading", "Thread", .class, "+Sleep(millisecondsTimeout As Integer) | +.CurrentThread As Thread | Start() | Join() | Name As String | IsAlive As Boolean | IsBackground As Boolean | ManagedThreadId As Integer"),
        ("System.Threading.Tasks", "Task", .class, "+Run(action As Action) As Task | +Delay(millisecondsDelay As Integer) As Task | +WhenAll(ParamArray tasks As Task()) As Task | +WhenAny(ParamArray tasks As Task()) As Task(Of Task) | +FromResult(result As T) As Task(Of T) | +.CompletedTask As Task | Wait() | ContinueWith(continuationAction As Action(Of Task)) As Task | IsCompleted As Boolean | IsFaulted As Boolean | Status As TaskStatus | Result As T"),
        ("System.Diagnostics", "Stopwatch", .class, "+StartNew() As Stopwatch | Start() | Stop() | Reset() | Restart() | Elapsed As TimeSpan | ElapsedMilliseconds As Long | IsRunning As Boolean"),
        ("System.Diagnostics", "Debug", .class, "+WriteLine(message As String) | +Write(message As String) | +Assert(condition As Boolean) | +Fail(message As String)"),
        ("System.Diagnostics", "Process", .class, "+Start(fileName As String) As Process | +GetCurrentProcess() As Process | +GetProcesses() As Process() | Kill() | WaitForExit() | Id As Integer | ProcessName As String | HasExited As Boolean | ExitCode As Integer | StandardOutput As StreamReader"),
        ("System.Net.Http", "HttpClient", .class, "GetAsync(requestUri As String) As Task(Of HttpResponseMessage) | GetStringAsync(requestUri As String) As Task(Of String) | PostAsync(requestUri As String, content As HttpContent) As Task(Of HttpResponseMessage) | PutAsync(requestUri As String, content As HttpContent) As Task(Of HttpResponseMessage) | DeleteAsync(requestUri As String) As Task(Of HttpResponseMessage) | SendAsync(request As HttpRequestMessage) As Task(Of HttpResponseMessage) | BaseAddress As Uri | DefaultRequestHeaders As HttpRequestHeaders | Timeout As TimeSpan | Dispose()"),
        ("System.Net.Http", "HttpResponseMessage", .class, "EnsureSuccessStatusCode() As HttpResponseMessage | IsSuccessStatusCode As Boolean | StatusCode As HttpStatusCode | Content As HttpContent | Headers As HttpResponseHeaders | ReasonPhrase As String"),
        ("System.Linq", "Enumerable", .class, "+Range(start As Integer, count As Integer) As IEnumerable(Of Integer) | +Repeat(element As T, count As Integer) As IEnumerable(Of T) | +Empty() As IEnumerable(Of T)"),
        ("System.Text.RegularExpressions", "Regex", .class, "+IsMatch(input As String, pattern As String) As Boolean | +Match(input As String, pattern As String) As Match | +Matches(input As String, pattern As String) As MatchCollection | +Replace(input As String, pattern As String, replacement As String) As String | +Split(input As String, pattern As String) As String() | +Escape(str As String) As String"),
        ("System.Text.Json", "JsonSerializer", .class, "+Serialize(value As Object) As String | +Deserialize(Of T)(json As String) As T"),
        ("Microsoft.VisualBasic", "Strings", .module, "+Len(str As String) As Integer | +Left(str As String, length As Integer) As String | +Right(str As String, length As Integer) As String | +Mid(str As String, start As Integer, length As Integer) As String | +UCase(str As String) As String | +LCase(str As String) As String | +Trim(str As String) As String | +InStr(string1 As String, string2 As String) As Integer | +Replace(expression As String, find As String, replacement As String) As String | +Split(expression As String, delimiter As String) As String() | +Join(sourceArray As String(), delimiter As String) As String | +Format(expression As Object, style As String) As String | +StrReverse(expression As String) As String | +Asc(c As Char) As Integer | +Chr(charCode As Integer) As Char"),
        ("Microsoft.VisualBasic", "Interaction", .module, "+MsgBox(prompt As Object) As MsgBoxResult | +InputBox(prompt As String) As String | +IIf(expression As Boolean, truePart As Object, falsePart As Object) As Object | +Beep() | +Shell(pathName As String) As Integer"),
        ("Microsoft.VisualBasic", "Conversion", .module, "+Val(expression As String) As Double | +Str(number As Object) As String | +Int(number As Double) As Double | +Fix(number As Double) As Double | +Hex(number As Object) As String | +Oct(number As Object) As String"),
        ("Microsoft.VisualBasic", "DateAndTime", .module, "+.Now As DateTime | +.Today As DateTime | +.TimeOfDay As DateTime | +DateAdd(interval As DateInterval, number As Double, dateValue As DateTime) As DateTime | +DateDiff(interval As DateInterval, date1 As DateTime, date2 As DateTime) As Long | +Year(dateValue As DateTime) As Integer | +Month(dateValue As DateTime) As Integer | +Day(dateValue As DateTime) As Integer"),
    ]

    /// LINQ, available on every collection.
    static let linq = "Where(predicate As Func(Of T, Boolean)) As IEnumerable(Of T) | Select(selector As Func(Of T, TResult)) As IEnumerable(Of TResult) | OrderBy(keySelector As Func(Of T, TKey)) As IOrderedEnumerable(Of T) | OrderByDescending(keySelector As Func(Of T, TKey)) As IOrderedEnumerable(Of T) | First() As T | FirstOrDefault() As T | Last() As T | LastOrDefault() As T | Single() As T | Any() As Boolean | All(predicate As Func(Of T, Boolean)) As Boolean | Count() As Integer | Sum() As Double | Average() As Double | Max() As T | Min() As T | ToList() As List(Of T) | ToArray() As T() | ToDictionary(keySelector As Func(Of T, TKey)) As Dictionary(Of TKey, T) | Distinct() As IEnumerable(Of T) | Take(count As Integer) As IEnumerable(Of T) | Skip(count As Integer) As IEnumerable(Of T) | GroupBy(keySelector As Func(Of T, TKey)) As IEnumerable(Of IGrouping(Of TKey, T)) | Aggregate(func As Func(Of T, T, T)) As T | Concat(second As IEnumerable(Of T)) As IEnumerable(Of T) | Reverse() As IEnumerable(Of T) | SequenceEqual(second As IEnumerable(Of T)) As Boolean"

    static let collections: Set<String> = ["List", "Dictionary", "HashSet", "Queue", "Stack", "Array", "String"]

    public static let types: [DotNetType] = source.map { namespace, name, kind, members in
        var list = parse(members)
        if kind == .class || kind == .structure, name != "Object" { list += parse(objectMembers) }
        if collections.contains(name) { list += parse(linq).filter { member in !list.contains { $0.name == member.name } } }
        return DotNetType(name: name, namespace: namespace, kind: kind, members: list)
    }

    private static let objectMembers = "ToString() As String | Equals(obj As Object) As Boolean | GetHashCode() As Integer | GetType() As Type"

    public static let namespaces: [String] = {
        var names = Set<String>()
        for type in types {
            var parts = type.namespace.split(separator: ".").map(String.init)
            while !parts.isEmpty {
                names.insert(parts.joined(separator: "."))
                parts.removeLast()
            }
        }
        return names.sorted()
    }()

    /// VB.NET and C# type keywords, and the .NET types they stand for.
    public static let aliases: [String: String] = [
        "integer": "Int32", "int": "Int32", "long": "Int64", "short": "Int16", "double": "Double", "single": "Single", "float": "Single",
        "decimal": "Decimal", "boolean": "Boolean", "bool": "Boolean", "char": "Char", "string": "String", "date": "DateTime",
        "object": "Object", "byte": "Byte", "int32": "Int32", "int64": "Int64",
    ]

    /// VB.NET's keywords as they're written (the highlighter keeps them in lower case).
    public static let vbKeywords = """
        AddHandler AddressOf And AndAlso As Boolean ByRef Byte ByVal Call Case Catch CBool CByte CChar CDate CDbl CDec Char CInt Class \
        CLng CObj Const Continue CShort CSng CStr CType Date Decimal Delegate Dim DirectCast Do Double Each Else ElseIf End Enum Erase \
        Error Event Exit False Finally For Friend Function Get GetType Global Handles If Implements Imports In Inherits Integer \
        Interface Is IsNot Let Like Long Loop Me Mod Module MustInherit MustOverride MyBase MyClass NameOf Namespace New Next Not \
        Nothing NotInheritable NotOverridable Object Of On Operator Option Optional Or OrElse Overloads Overridable Overrides \
        ParamArray Partial Private Property Protected Public RaiseEvent ReadOnly ReDim RemoveHandler Return Select Set Shadows \
        Shared Short Single Static Step Stop String Structure Sub SyncLock Then Throw To True Try TryCast TypeOf Using When While \
        With WithEvents WriteOnly Xor Async Await Iterator Yield
        """.split(separator: " ").map(String.init)

    /// A type by name, ignoring case, generic arguments and array brackets: "List(Of String)", "list<int>", "Integer".
    public static func type(named raw: String) -> DotNetType? {
        let name = baseName(raw)
        if name.hasSuffix("()") || name.hasSuffix("[]") { return types.first { $0.name == "Array" } }
        let resolved = aliases[name.lowercased()] ?? name
        let short = resolved.split(separator: ".").last.map(String.init) ?? resolved
        return types.first { $0.name.lowercased() == short.lowercased() }
    }

    /// "List(Of String)" → "List", "Dictionary<string, int>" → "Dictionary", "String()" stays an array.
    public static func baseName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("New ") || name.hasPrefix("new ") { name = String(name.dropFirst(4)) }
        if let open = name.range(of: "(Of ", options: .caseInsensitive) { name = String(name[..<open.lowerBound]) }
        if let open = name.firstIndex(of: "<") { name = String(name[..<open]) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private static func parse(_ text: String) -> [DotNetMember] {
        text.components(separatedBy: " | ").compactMap { raw in
            var entry = raw.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { return nil }
            let isShared = entry.hasPrefix("+")
            if isShared { entry.removeFirst() }
            if entry.hasPrefix(".") { entry.removeFirst() }
            let isMethod = entry.contains("(") && !(entry.firstIndex(of: "(")! > (entry.range(of: " As ")?.lowerBound ?? entry.endIndex))
            let name = String(entry.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            var returnType: String?
            if isMethod {
                // Skip the parameter list (and a leading `(Of T)`); what follows " As " is the return type.
                var rest = Substring(entry[entry.firstIndex(of: "(")!...])
                while rest.hasPrefix("(") {
                    var depth = 0
                    var end = rest.startIndex
                    for index in rest.indices {
                        if rest[index] == "(" { depth += 1 }
                        if rest[index] == ")" { depth -= 1; if depth == 0 { end = index; break } }
                    }
                    rest = rest[rest.index(after: end)...]
                }
                if rest.hasPrefix(" As ") { returnType = String(rest.dropFirst(4)) }
            } else if let range = entry.range(of: " As ") {
                returnType = String(entry[range.upperBound...])
            }
            return DotNetMember(name: name, isShared: isShared, isMethod: isMethod, signature: entry, returnType: returnType)
        }
    }
}
