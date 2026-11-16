import Foundation

/// Plain-language explanations of the errors beginners meet most, for every language Kryndev builds or checks: what the
/// compiler means and what usually fixes it. Shown under the error in the hover and in the Error List. (The Windows version
/// has the same rules.)
public enum ErrorExplanations {
    /// (language, error code or message pattern, explanation); a nil language is any language.
    private static let rules: [(language: String?, pattern: String, explanation: String)] = [
        ("csharp", #"\bCS0103\b"#, "A name is used that doesn't exist here. Check the spelling (C# is case-sensitive), that the variable is declared before this line and in this block, or add the missing using."),
        ("csharp", #"\bCS1002\b"#, "A statement isn't finished: add a semicolon ; at the end of the line."),
        ("csharp", #"\bCS1513\b"#, "A closing brace } is missing. Every { needs a matching }."),
        ("csharp", #"\bCS1026\b"#, "A closing parenthesis ) is missing."),
        ("csharp", #"\bCS0029\b"#, "A value of one type is put where another type is expected (like text into a number). Convert it first, for example int.Parse(text) or value.ToString()."),
        ("csharp", #"\bCS0266\b"#, "The conversion could lose information, so C# wants you to ask for it: add a cast like (int)value."),
        ("csharp", #"\bCS0246\b"#, "A type or namespace isn't known. Check the spelling, add the using for its namespace, or add the package or reference that has it."),
        ("csharp", #"\bCS1061\b"#, "This type has no member with that name. Check the spelling and the type of the value before the dot."),
        ("csharp", #"\bCS0117\b"#, "This type has no member with that name. Check the spelling and the type before the dot."),
        ("csharp", #"\bCS0161\b"#, "Some paths through the method end without returning a value. Add a return statement at the end (or in the missing else)."),
        ("csharp", #"\bCS0165\b"#, "The variable is read before anything is stored in it. Give it a value when you declare it."),
        ("csharp", #"\bCS0120\b"#, "An instance member is used from a static method. Create an object first (new MyClass()) or make the member static."),
        ("csharp", #"\bCS0128\b"#, "A variable with this name is already declared in this method. Use another name or reuse the first one."),
        ("csharp", #"\bCS0136\b"#, "This name is already used by a variable in an enclosing block. Give one of them another name."),
        ("csharp", #"\bCS0019\b"#, "This operator doesn't work with these two types, for example adding a number to a bool. Check both values' types."),
        ("csharp", #"\bCS1503\b"#, "An argument has the wrong type for this parameter. Convert it, or call the method with a value of the expected type."),
        ("csharp", #"\bCS7036\b"#, "A required argument is missing from the call. Look at Parameter Info (Ctrl+Shift+Space) for what the method needs."),
        ("csharp", #"\bCS1501\b"#, "No version of this method takes that many arguments. Check how many the method expects."),
        ("csharp", #"\bCS0111\b"#, "A member with this name and the same parameters is already declared in this type."),
        ("csharp", #"\bCS0101\b"#, "The namespace already has a type with this name. Rename one of them, or delete the duplicate file."),
        ("csharp", #"\bCS0815\b"#, "var needs a value it can work the type out from; null alone isn't enough. Give the type instead of var."),
        ("csharp", #"\bCS86(00|01|02|03|04)\b"#, "Nullable warning: this value could be null here. Check it first (if (x != null)) or use x?.Member."),
        ("csharp", #"\bCS0168\b"#, "The variable is declared but never used. Remove it, or use it."),
        ("csharp", #"\bCS0219\b"#, "The variable gets a value that is never used. Remove it, or use it."),
        ("csharp", #"\bCS0162\b"#, "This code can never run, because of a return, break or throw before it."),
        ("csharp", #"\bCS5001\b"#, "The program has no Main method (or top-level statements) to start from."),
        ("vb", #"\bBC30451\b"#, "A name is used that isn't declared. Check the spelling, declare it with Dim, or add the missing Imports."),
        ("vb", #"\bBC30002\b"#, "A type isn't defined. Check the spelling, or add the Imports for its namespace or the reference that has it."),
        ("vb", #"\bBC30456\b"#, "This type has no member with that name. Check the spelling and the type before the dot."),
        ("vb", #"\bBC30311\b"#, "A value of one type can't be converted to the type that's needed. Convert it with CInt, CStr, CDbl…"),
        ("vb", #"\bBC30512\b"#, "Option Strict On doesn't allow this automatic conversion. Convert explicitly with CInt, CDbl, CStr…"),
        ("vb", #"\bBC30205\b"#, "The line has more after the end of the statement. Split it into two lines, or remove the extra text."),
        ("vb", #"\bBC30081\b"#, "An If has no matching End If."),
        ("vb", #"\bBC30026\b"#, "A Sub has no matching End Sub."),
        ("vb", #"\bBC30027\b"#, "A Function has no matching End Function."),
        ("vb", #"\bBC30084\b"#, "A For has no matching Next."),
        ("vb", #"\bBC42104\b"#, "The variable is used before it's given a value; it could be Nothing. Give it a value when you declare it."),
        ("vb", #"\bBC30057\b"#, "The call has more arguments than the method accepts."),
        ("vb", #"\bBC30455\b"#, "A required argument is missing from the call."),
        ("vb", #"\bBC42105\b"#, "Some paths through the Function end without returning a value. Add a Return at the end."),
        ("c", #"use of undeclared identifier|was not declared in this scope|undeclared \(first use"#, "A name is used that isn't declared. Check the spelling, declare the variable first, or #include the header that declares it."),
        ("c", #"implicit declaration of function"#, "The function is called before C knows about it. #include its header, or declare the function above this line."),
        ("c", #"undefined reference to|Undefined symbols? for architecture|unresolved external symbol"#, "The linker can't find the function's code: it's declared but not defined, or the file or library that defines it isn't part of the build."),
        ("c", #"expected ';'"#, "A semicolon ; is missing, usually at the end of this line or the one before."),
        ("c", #"expected '\)'"#, "A closing parenthesis ) is missing."),
        ("c", #"expected '\}'|expected declaration or statement at end of input"#, "A closing brace } is missing. Every { needs a matching }."),
        ("c", #"no matching function for call"#, "No version of this function takes these arguments. Check their number and types."),
        ("c", #"control reaches end of non-void function|non-void function does not return a value"#, "The function should return a value but can reach its end without one. Add a return at the end."),
        ("c", #"incompatible pointer|incompatible (integer|types)|cannot convert|invalid conversion"#, "A value of one type is used where another is needed. Check the types, or convert the value."),
        ("c", #"too few arguments"#, "The call is missing arguments the function needs."),
        ("c", #"too many arguments"#, "The call has more arguments than the function takes."),
        ("c", #"no member named|has no member named"#, "This struct or class has no member with that name. Check the spelling and the type."),
        ("c", #"redefinition of|redeclared|conflicting types for"#, "The same name is declared twice. Remove one, or rename it."),
        ("c", #"is (used )?uninitialized|may be used uninitialized"#, "The variable is read before it's given a value. Initialize it where it's declared."),
        ("c", #"unused variable"#, "The variable is declared but never used. Remove it, or use it."),
        ("c", #"format specifies type|format '%.*' expects"#, "The printf/scanf format doesn't match the argument: %d is for int, %f for double, %s for strings, %c for char."),
        ("c", #"Segmentation fault|SIGSEGV"#, "The program read or wrote memory it doesn't own: a NULL pointer, an array index past the end, or memory already freed."),
        ("python", #"NameError|is not defined"#, "A name is used that doesn't exist yet. Check the spelling (Python is case-sensitive), define the variable above this line, or import it."),
        ("python", #"IndentationError: expected an indented block|expected an indented block"#, "After a line ending in a colon (if, for, def, class…) the next lines must be indented."),
        ("python", #"IndentationError: unexpected indent|unexpected indent"#, "This line is indented more than it should be. Line it up with the lines around it."),
        ("python", #"unindent does not match|inconsistent use of tabs"#, "The indentation doesn't line up with an earlier level; don't mix tabs and spaces."),
        ("python", #"expected ':'"#, "A colon : is missing at the end of the if, for, while, def or class line."),
        ("python", #"can only concatenate str|unsupported operand type"#, "Two values of different types are combined, like text + a number. Convert one: str(number) or int(text)."),
        ("python", #"takes \d+ positional arguments? but \d+ (were|was) given|missing \d+ required positional argument"#, "The function is called with the wrong number of arguments. Remember that methods get self automatically."),
        ("python", #"object is not callable"#, "Something that isn't a function is called with (). A variable may have the same name as a function."),
        ("python", #"object is not subscriptable"#, "[ ] is used on a value that isn't a list, string or dictionary (often None, or a function you forgot to call)."),
        ("python", #"AttributeError|has no attribute"#, "The value has no attribute or method with that name. Check the spelling and the value's type; it may be None."),
        ("python", #"IndexError|index out of range"#, "The index is past the end: a list with 3 items has indexes 0, 1 and 2."),
        ("python", #"KeyError"#, "The dictionary has no such key. Check it first with if key in d, or use d.get(key)."),
        ("python", #"invalid literal for int\(\)"#, "The text isn't a whole number, so int() can't convert it. Check what was typed, or use float() for decimals."),
        ("python", #"ZeroDivisionError|division by zero"#, "A number is divided by zero. Check the divisor first."),
        ("python", #"ModuleNotFoundError|No module named|Import .* could not be resolved"#, "The module isn't installed or the name is misspelled. Install it with pip install <name>."),
        ("python", #"FileNotFoundError|No such file or directory"#, "The file doesn't exist at that path. Check the name, and that the path is relative to the folder the program runs in."),
        ("python", #"UnboundLocalError|is possibly unbound|referenced before assignment"#, "The variable is used before it gets a value on every path. Give it a value before the if or loop."),
        ("python", #"RecursionError|maximum recursion depth"#, "A function keeps calling itself without stopping. Check its stopping condition."),
        ("python", #"invalid syntax|SyntaxError"#, "Python can't read this line: look for a missing colon, bracket or quote, here or on the line before."),
        ("javascript", #"\bTS2304\b|ReferenceError|Cannot find name"#, "A name is used that isn't declared. Check the spelling, declare it with let or const, or import it."),
        ("javascript", #"\bTS2322\b|is not assignable to type"#, "A value of one type is put where another type is expected. Check the variable's type, or convert the value."),
        ("javascript", #"\bTS2339\b|Property '.*' does not exist"#, "The object has no property with that name. Check the spelling and the object's type."),
        ("javascript", #"\bTS2345\b|Argument of type"#, "An argument has the wrong type for this parameter."),
        ("javascript", #"\bTS2554\b|Expected \d+ arguments?, but got"#, "The function is called with the wrong number of arguments."),
        ("javascript", #"\bTS7006\b|implicitly has an 'any' type"#, "TypeScript can't tell this parameter's type. Add one: (name: string)."),
        ("javascript", #"\bTS2451\b|Cannot redeclare block-scoped variable"#, "A let or const with this name is already declared in this scope."),
        ("javascript", #"\bTS2307\b|Cannot find module"#, "The module isn't installed or the path is wrong. Install it with npm install <name>, or fix the path."),
        ("javascript", #"Cannot read propert(y|ies) of (undefined|null)"#, "The code uses .something on a value that is undefined or null. Check that the value is set before using it."),
        ("javascript", #"is not a function"#, "Something that isn't a function is called with (). Check the spelling, and that the value is what you think it is."),
        ("javascript", #"Unexpected token"#, "JavaScript can't read the code here: look for a missing or extra bracket, comma or quote."),
        ("javascript", #"Assignment to constant variable"#, "A const can't be given a new value. Use let if it needs to change."),
        ("java", #"cannot find symbol"#, "A name is used that isn't declared. Check the spelling (Java is case-sensitive), declare it first, or import the class."),
        ("java", #"incompatible types"#, "A value of one type is used where another is needed. Convert it, for example Integer.parseInt(text)."),
        ("java", #"';' expected"#, "A semicolon ; is missing at the end of the statement."),
        ("java", #"missing return statement"#, "Some paths through the method end without returning a value. Add a return at the end."),
        ("java", #"might not have been initialized"#, "The variable is read before it's given a value. Initialize it where it's declared."),
        ("java", #"is public, should be declared in a file named"#, "A public class must be in a file with the same name: class Hello goes in Hello.java."),
        ("java", #"unreported exception"#, "This call can throw a checked exception. Put it in try/catch, or add throws to the method."),
        ("java", #"NullPointerException"#, "The code uses a value that is null. Check that the object was created before using it."),
        ("java", #"ArrayIndexOutOfBoundsException|StringIndexOutOfBoundsException"#, "The index is past the end: an array of length 3 has indexes 0, 1 and 2."),
        ("go", #"undefined: "#, "A name is used that isn't declared. Check the spelling, declare it, or import its package."),
        ("go", #"declared and not used|declared but not used"#, "Go doesn't allow unused variables. Use it, remove it, or assign it to _."),
        ("go", #"imported and not used"#, "Go doesn't allow unused imports. Remove the import, or use the package."),
        ("go", #"missing return"#, "The function should return a value but can reach its end without one. Add a return at the end."),
        ("go", #"non-declaration statement outside function body"#, "Statements must be inside a function; := works only inside functions too."),
        ("go", #"no new variables on left side of :="#, "All the variables on the left already exist. Use = to assign to them."),
        ("go", #"assignment mismatch"#, "The number of variables on the left doesn't match the number of values on the right."),
        ("rust", #"\bE0425\b|cannot find value"#, "A name is used that isn't declared in this scope. Check the spelling, or declare it with let first."),
        ("rust", #"\bE0308\b|mismatched types"#, "A value has a different type than expected. Check the declared type, or convert the value."),
        ("rust", #"\bE0382\b|use of moved value|borrow of moved value"#, "The value was moved somewhere else and can't be used again. Borrow it with & instead, or .clone() it."),
        ("rust", #"\bE0384\b|cannot assign twice to immutable variable"#, "Variables can't change unless they're declared with let mut."),
        ("rust", #"\bE0502\b|\bE0499\b|cannot borrow"#, "The value is borrowed in a conflicting way: only one mutable borrow, or many shared ones, at a time."),
        ("rust", #"\bE0599\b|no method named"#, "This type has no method with that name. Check the spelling, and whether a trait needs to be imported with use."),
        ("rust", #"\bE0433\b|failed to resolve"#, "A path or module isn't found. Check the spelling, or add the use or dependency."),
        ("swift", #"cannot find '.*' in scope|use of unresolved identifier"#, "A name is used that isn't declared here. Check the spelling, declare it first, or import the module."),
        ("swift", #"value of optional type .* must be unwrapped"#, "This value may be nil. Unwrap it with if let, guard let or ??, rather than using it directly."),
        ("swift", #"cannot assign to value: '.*' is a 'let' constant"#, "A let can't change. Declare it with var if it needs to."),
        ("swift", #"missing return in"#, "The function should return a value but can reach its end without one."),
        ("swift", #"has no member"#, "This type has no member with that name. Check the spelling and the value's type."),
        ("swift", #"was never mutated; consider changing to 'let'"#, "The variable never changes, so it can be a let."),
        ("swift", #"was never used"#, "The value is never used. Remove it, or replace the name with _."),
        (nil, #"unterminated string|unclosed string|missing terminating|EOL while scanning string|unterminated string literal"#, "A string is missing its closing quote."),
        (nil, #"Access is denied|Permission denied"#, "The program isn't allowed to open the file or folder. Close other programs that use it, or check its permissions."),
    ]

    private static let compiled: [NSRegularExpression?] = rules.map { try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) }

    /// What an error means and how to fix it, or nil when there's no explanation for it. Without a language (an error from a
    /// build log, say) every language's rules are tried.
    public static func explain(_ message: String, code: String? = nil, languageId: String? = nil) -> String? {
        let text = (code?.isEmpty == false ? code! + " " : "") + message
        let range = NSRange(location: 0, length: (text as NSString).length)
        let group = family(of: languageId)
        for (i, rule) in rules.enumerated() where group == nil || rule.language == nil || rule.language == group {
            if compiled[i]?.firstMatch(in: text, range: range) != nil { return rule.explanation }
        }
        return nil
    }

    /// Languages that share their compiler's messages are explained by one set of rules.
    private static func family(of languageId: String?) -> String? {
        switch languageId {
        case nil: nil
        case "cpp", "objc", "objcpp": "c"
        case "typescript", "javascriptreact", "typescriptreact": "javascript"
        default: languageId
        }
    }
}
