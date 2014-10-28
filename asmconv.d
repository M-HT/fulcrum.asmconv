import std.stdio;
import std.string;
import std.c.stdlib;
import std.conv;

immutable(uint) maximum_lookahead = 5;

string[7] regs_list = ["eax", "ebx", "ecx", "edx", "esi", "edi", "ebp"];

struct inputline {
    string orig, line, comment;
    string[2] word;
}

struct asm_var {
    string name, type_name;
    uint linenum, size, offset, numitems;
    bool inttype, floattype, structype, argument;
}

struct asm_struc {
    string name;
    uint linenum, size;
    bool isunion;
    asm_var[] vars;
}

struct asm_const {
    string name, value;
    uint linenum;
}

enum PT {
    none,
    register,
    reg_ebp,
    fpu_reg,
    memory,
    stack_variable,
    local_variable,
    local_struc_variable,
    displaced_local_variable,
    variable,
    struc_variable,
    constant,
    struc_var_offset,
    procedure_address,
    local_label
}

enum PF {
    none = 0,
    signed = 1,
    addressof = 2,
    floattype = 4
}

enum FF {
    read = 1,
    write = 2,
    rw = 3
}

enum FPU_RC {
    NONE = 0,
    NEAREST,
    DOWN,
    UP,
    ZERO
}

enum FPU_DT {
    NONE = 0,
    FLOAT,
    DOUBLE
}

struct instruction_parameter {
    string paramstr;
    PT type;
    uint size;
    string base, index, displacement;
    uint index_mult;
    bool isstructref, isvariablearray;
    string struct_name, struct_ref;
    PT var_type;
    string var_name;
}

struct asm_reg {
    string name, value;
    bool used, read_unknown, trashed;
}

struct asm_fpu_reg {
    bool read, write, read_unknown;
}

struct asm_state {
    asm_reg[string] regs;
    asm_fpu_reg[] fpu_regs;
    string[] stack_value;
    int stack_index, stack_max_index, fpu_index, fpu_max_index, fpu_min_index;

    this(this)
    {
        regs = regs.dup;
        fpu_regs = fpu_regs.dup;
        stack_value = stack_value.dup;
    }
}

struct asm_label {
    string name;
    uint linenum;
    asm_state state;
}

enum PPT {
    none,
    register,
    fpu_reg,
    variable
}

struct asm_proc_param {
    string name;
    PPT type;
    bool input, output, floatarg;
    byte fpuindex;
}

struct asm_proc {
    string name, filename;
    bool public_proc;
    FPU_RC rounding_mode;
    FPU_DT fpureg_datatype;
    asm_proc_param[] arguments;
    string return_reg;
    bool[string] input_regs_list;
    bool[string] output_regs_list;
    bool[string] scratch_regs_list;
    int fpu_index;
    bool[byte] input_fpu_regs_list; // 0,-1,-2,...
    bool[byte] output_fpu_regs_list; // 0,-1,-2,...
    bool[byte] scratch_fpu_regs_list; // 0,-1,-2,...
}

struct asm_file {
    string name;
    FPU_RC rounding_mode;
}

inputline[] lines;
string[][] output_lines;
uint current_line;

FPU_RC rounding_mode = FPU_RC.NONE;
bool rounding_mode_first = true;
FPU_DT fpureg_datatype = FPU_DT.DOUBLE;
string fpureg_datatype_name = "double";
string fpureg_datatype_suffix = "";

// global variables
string current_file_name;
asm_struc[] structures;
asm_var[] variables;
asm_const[] constants;
asm_proc[] procedures;
asm_file[] files;
asm_file *current_input_file;

// procedure variables
string procedure_name;
int procedure_linenum;
asm_proc *current_procedure;
asm_var[] local_variables;
asm_label[] local_labels;
asm_state current_state;

// instruction variables
instruction_parameter[] instr_params;

string get_rounding_function()
{
    if (rounding_mode_first)
    {
        rounding_mode_first = false;
        stdout.writeln("------------------");
        stdout.write("FPU rounding mode: ");
        switch (rounding_mode)
        {
            case FPU_RC.NEAREST:
                stdout.writeln("nearest");
                break;
            case FPU_RC.DOWN:
                stdout.writeln("down");
                break;
            case FPU_RC.UP:
                stdout.writeln("up");
                break;
            case FPU_RC.ZERO:
                stdout.writeln("zero");
                break;
            default:
                stdout.writeln("unknown");
                if (current_input_file != null)
                {
                    stderr.writeln("Error: unknown FPU rounding mode");
                    exit(1);
                }
                break;
        }
        stdout.writeln("------------------");
    }

    switch (rounding_mode)
    {
        case FPU_RC.NEAREST:
            return "round" ~ fpureg_datatype_suffix;
        case FPU_RC.DOWN:
            return "floor" ~ fpureg_datatype_suffix;
        case FPU_RC.UP:
            return "ceil" ~ fpureg_datatype_suffix;
        case FPU_RC.ZERO:
            return "trunc" ~ fpureg_datatype_suffix;
        default:
            return "(int)";
    }
}

bool substr_from_entry_equal(string str, uint entry, dchar delim, string eqstr)
{
    int index = 0;
    while (entry > 0)
    {
        int newindex = cast(int)str[index..$].indexOf(delim);
        if (newindex == -1)
        {
            return (eqstr == "");
        }

        index += newindex + 1;
        entry --;
    };
    return (str[index..$] == eqstr);
}

string substr_from_entry(string str, uint entry, dchar delim)
{
    int index = 0;
    while (entry > 0)
    {
        int newindex = cast(int)str[index..$].indexOf(delim);
        if (newindex == -1)
        {
            return "".idup;
        }

        index += newindex + 1;
        entry --;
    };
    return str[index..$].idup;
}

string str_entry(string str, uint entry, dchar delim)
{
    int index = 0;
    int newindex;
    while (entry > 0)
    {
        newindex = cast(int)str[index..$].indexOf(delim);
        if (newindex == -1)
        {
            return "".idup;
        }

        index += newindex + 1;
        entry --;
    };

    newindex = cast(int)str[index..$].indexOf(delim);
    if (newindex == -1)
    {
        return str[index..$].idup;
    }
    else
    {
        return str[index..index+newindex].idup;
    }
}

string[] str_split_strip(string str, dchar delim)
{
    string[] res;

    res.length = 0;

    while (str != "")
    {
        int nextpos = cast(int)str.indexOf(delim);

        int cur = cast(int)res.length;
        res.length++;

        if (nextpos == -1)
        {
            res[cur] = str.idup;
            str = "";
        }
        else
        {
            res[cur] = str[0..nextpos].stripRight().idup;
            str = str[nextpos + 1..$].stripLeft();
        }
    }

    return res;
}

/*string[] str_split_strip(string str, string delims)
{
    string[] res;

    res.length = 0;

    while (str != "")
    {
        int nextpos = -1;
        foreach (delim; delims)
        {
            int pos = cast(int)str.indexOf(delim);
            if (nextpos == -1 || nextpos > pos) nextpos = pos;
        }

        int cur = cast(int)res.length;
        res.length++;

        if (nextpos == -1)
        {
            res[cur] = str.idup;
            str = "";
        }
        else
        {
            res[cur] = str[0..nextpos].stripRight().idup;
            str = str[nextpos + 1..$].stripLeft();
        }
    }

    return res;
}*/


asm_struc *find_struc(string struc_name)
{
    foreach (i, ref s; structures)
    {
        if (s.name == struc_name)
        {
            return &structures[i];
        }
    }
    return null;
}

asm_struc *find_struc_with_var(string var_name)
{
    asm_struc *res = null;

    foreach (i, ref s; structures)
    {
        foreach (ref v; s.vars)
        {
            if (v.name == var_name)
            {
                if (res == null)
                {
                    res = &structures[i];
                }
                else
                {
                    return null;
                }
            }
        }
    }

    return res;
}

asm_struc *find_struc_by_ref(string struc_ref)
{
    auto names = str_split_strip(struc_ref, '.');

    asm_struc *res = find_struc_with_var(names[0]);

    if (res == null) return null;

    auto struct_def = res;

    foreach (var_index; 0..names.length)
    {
        asm_var *var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null) return null;

        if (var_index == names.length - 1)
        {
            return res;
        }

        if (!var.structype) return null;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return null;
    }

    return null;
}

asm_var *find_local_variable(string var_name)
{
    foreach (i, ref v; local_variables)
    {
        if (v.name == var_name)
        {
            return &local_variables[i];
        }
    }
    return null;
}

asm_var *find_variable(string var_name)
{
    foreach (i, ref v; variables)
    {
        if (v.name == var_name)
        {
            return &variables[i];
        }
    }
    return null;
}

asm_var *find_local_struct_variable(string var_name)
{
    auto names = str_split_strip(var_name, '.');

    if (names.length < 2) return null;
    auto var = find_local_variable(names[0]);
    if (var == null) return null;

    if (!var.structype)
    {
        if (var.numitems < 2) return null;
        if (var.inttype || var.floattype) return null;

        auto local_struct = find_struc_with_var(names[1]);
        if (local_struct == null) return null;
        if (local_struct.size != var.size * var.numitems) return null;

        var.structype = true;
        var.numitems = 1;
        var.type_name = local_struct.name.idup;
    }

    auto struct_def = find_struc(var.type_name);
    if (struct_def == null) return null;

    foreach (var_index; 1..names.length)
    {
        var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null) return null;

        if (var_index == names.length - 1)
        {
            return var;
        }

        if (!var.structype) return null;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return null;
    }

    return null;
}

asm_var *find_struct_variable(string var_name)
{
    auto names = str_split_strip(var_name, '.');

    if (names.length < 2) return null;
    auto var = find_variable(names[0]);
    if (var == null) return null;
    if (!var.structype) return null;
    auto struct_def = find_struc(var.type_name);
    if (struct_def == null) return null;

    foreach (var_index; 1..names.length)
    {
        var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null)
        {
            auto inner_struct = find_struc_with_var(names[var_index]);
            if (inner_struct == null) return null;

            foreach (i, ref v; struct_def.vars)
            {
                if (v.type_name == inner_struct.name)
                {
                    var = &struct_def.vars[i];
                    break;
                }
            }
            if (var == null) return null;

            var = null;
            foreach (i, ref v; inner_struct.vars)
            {
                if (v.name == names[var_index])
                {
                    var = &inner_struct.vars[i];
                    break;
                }
            }
            if (var == null) return null;
        }

        if (var_index == names.length - 1)
        {
            return var;
        }

        if (!var.structype) return null;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return null;
    }

    return null;
}

asm_var *find_struct_variable_by_ref(string struct_name, string struct_ref)
{
    auto names = str_split_strip(struct_ref, '.');

    auto struct_def = find_struc(struct_name);

    foreach (var_index; 0..names.length)
    {
        asm_var *var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null) return null;

        if (var_index == names.length - 1)
        {
            return var;
        }

        if (!var.structype) return null;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return null;
    }

    return null;
}

asm_const *find_constant(string const_name)
{
    foreach (i, ref c; constants)
    {
        if (c.name == const_name)
        {
            return &constants[i];
        }
    }
    return null;
}

asm_label *find_local_label(string label_name)
{
    foreach (i, ref l; local_labels)
    {
        if (l.name == label_name)
        {
            return &(local_labels[i]);
        }
    }
    return null;
}

asm_proc *find_proc(string proc_name)
{
    foreach (i, ref p; procedures)
    {
        if (p.name == proc_name)
        {
            if (current_file_name == p.filename || p.public_proc)
            {
                return &procedures[i];
            }
        }
    }
    return null;
}

int get_common_struct_variables_size(string struct_name)
{
    auto struct_def = find_struc(struct_name);
    int size = -1;

    foreach (v; struct_def.vars)
    {
        if (size == -1)
        {
            size = v.size;
        }
        else if (size != v.size)
        {
            return 0;
        }
    }

    if (size > 0)
    {
        return size;
    }
    else
    {
        return 0;
    }
}

string get_struct_variable_reference(string var_name)
{
    auto names = str_split_strip(var_name, '.');

    if (names.length < 2) return "".idup;
    auto var = find_variable(names[0]);
    if (var == null) return "".idup;
    if (!var.structype) return "".idup;
    auto struct_def = find_struc(var.type_name);
    if (struct_def == null) return "".idup;

    string res = var.name.idup;

    foreach (var_index; 1..names.length)
    {
        var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null)
        {
            auto inner_struct = find_struc_with_var(names[var_index]);
            if (inner_struct == null) return "".idup;

            foreach (i, ref v; struct_def.vars)
            {
                if (v.type_name == inner_struct.name)
                {
                    var = &struct_def.vars[i];
                    break;
                }
            }
            if (var == null) return "".idup;

            res = res ~ "." ~ var.name;

            var = null;
            foreach (i, ref v; inner_struct.vars)
            {
                if (v.name == names[var_index])
                {
                    var = &inner_struct.vars[i];
                    break;
                }
            }
            if (var == null) return "".idup;
        }

        res = res ~ "." ~ var.name;

        if (var_index == names.length - 1)
        {
            return res;
        }

        if (!var.structype) return "".idup;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return "".idup;
    }

    return "".idup;
}

string get_struct_variable_reference_by_ref(string struct_name, string struct_ref)
{
    auto names = str_split_strip(struct_ref, '.');
    if (names.length <= 1)
    {
        return struct_ref.idup;
    }

    auto struct_def = find_struc(struct_name);

    string res = "".idup;

    foreach (var_index; 0..names.length)
    {
        asm_var *var = null;
        foreach (i, ref v; struct_def.vars)
        {
            if (v.name == names[var_index])
            {
                var = &struct_def.vars[i];
                break;
            }
        }
        if (var == null) return "".idup;

        if (res != "") res = res ~ ".";
        res = res ~ var.name;

        if (var_index == names.length - 1)
        {
            return res;
        }
        else
        {
            if (var.numitems != 1)
            {
                res = res ~ "[0]";
            }
        }

        if (!var.structype) return "".idup;
        struct_def = find_struc(var.type_name);
        if (struct_def == null) return "".idup;
    }

    return "".idup;
}

bool is_number(string str_num)
{
    if (str_num[str_num.length-1] == 'h')
    {
        foreach(c; str_num[0..str_num.length-1].toLower())
        {
            if ("0123456789abcdef".indexOf(c) == -1)
            {
                return false;
            }
        }

        return true;
    }
    else
    {
        try
        {
            int num = to!int(str_num);
            return true;
        }
        catch (Exception e)
        {
            return false;
        }
    }
}

int get_number_value(string str_num)
{
    if (str_num[str_num.length-1] == 'h')
    {
        int result = 0;

        foreach(c; str_num[0..str_num.length-1].toLower())
        {
            result = result * 16 + cast(int)("0123456789abcdef".indexOf(c));
        }

        return result;
    }
    else
    {
        return to!int(str_num);
    }
}

bool is_constant_expression(string expr)
{
    while (expr != "")
    {
        int nextpos = -1;
        foreach (c; "+-*/()")
        {
            int pos = cast(int)expr.indexOf(c);
            if (pos != -1)
            {
                if (nextpos == -1 || nextpos > pos) nextpos = pos;
            }
        }

        int shlpos = cast(int)expr.indexOf(" shl ");
        int shrpos = cast(int)expr.indexOf(" shr ");
        int shiftpos;
        if (shlpos != -1)
        {
            if (shrpos != -1)
            {
                shiftpos = (shrpos < shlpos)?shrpos:shlpos;
            }
            else
            {
                shiftpos = shlpos;
            }
        }
        else
        {
            shiftpos = shrpos;
        }


        string expr_part;

        if (nextpos == -1 && shiftpos == -1)
        {
            expr_part = expr;
            expr = "";
        }
        else if (shiftpos == -1 || (nextpos != -1 && nextpos < shiftpos))
        {
            expr_part = expr[0..nextpos].stripRight();
            expr = expr[nextpos + 1..$].stripLeft();
        }
        else
        {
            expr_part = expr[0..shiftpos].stripRight();
            expr = expr[shiftpos + 5..$].stripLeft();
        }

        if (expr_part == "")
        {
            // ok
        }
        else if (find_constant(expr_part) != null)
        {
            // ok
        }
        else if (expr_part.length > 5 && expr_part[0..5] == "size " && find_struc(expr_part[5..$]) != null)
        {
            // ok
        }
        else if (is_number(expr_part))
        {
            // ok
        }
        else
        {
            return false;
        }
    }

    return true;
}

bool is_struc_var_offset(string var_offset)
{
    auto parts = str_split_strip(var_offset, ' ');

    if (parts.length == 2 && parts[0] == "offset" && find_struc_by_ref(parts[1]) != null)
    {
        return true;
    }
    else
    {
        return false;
    }
}

bool is_register(string reg)
{
    foreach (regname; regs_list)
    {
        if (reg == regname)
        {
            return true;
        }
    }

    return false;
}

bool is_fpu_register(string fpu_reg)
{
    if (fpu_reg == "st(0)" || fpu_reg == "st(1)" || fpu_reg == "st(2)" || fpu_reg == "st(3)" || fpu_reg == "st(4)" || fpu_reg == "st(5)" || fpu_reg == "st(6)" || fpu_reg == "st(7)")
    {
        return true;
    }
    else
    {
        return false;
    }
}

bool is_fpu_register2(string fpu_reg)
{
    if (fpu_reg == "st(-1)" || fpu_reg == "st(-2)" || fpu_reg == "st(-3)" || fpu_reg == "st(-4)" || fpu_reg == "st(-5)" || fpu_reg == "st(-6)" || fpu_reg == "st(-7)")
    {
        return true;
    }
    else
    {
        return false;
    }
}

bool is_register4_list(string list)
{
    auto regs = str_split_strip(list, ' ');

    foreach (reg; regs)
    {
        if (!is_register(reg))
        {
            return false;
        }
    }

    return true;
}

bool register_has_unknown_value(string reg)
{
    if ((current_state.regs[reg].value == "") || (is_register(current_state.regs[reg].value) && current_procedure != null && current_state.regs[reg].value in current_procedure.input_regs_list))
    {
        return false;
    }
    else
    {
        return true;
    }
}

bool is_instruction_prefix(string instr_str)
{
    if (instr_str == "rep"
       )
    {
        return true;
    }
    return false;
}

bool is_x86_instruction(string instr_str)
{
    if (instr_str == "push"
     || instr_str == "mov"
     || instr_str == "imul"
     || instr_str == "add"
     || instr_str == "cmp"
     || instr_str == "jne"
     || instr_str == "jbe"
     || instr_str == "jb"
     || instr_str == "jmp"
     || instr_str == "sub"
     || instr_str == "neg"
     || instr_str == "cdq"
     || instr_str == "idiv"
     || instr_str == "or"
     || instr_str == "jns"
     || instr_str == "jae"
     || instr_str == "lea"
     || instr_str == "inc"
     || instr_str == "shl"
     || instr_str == "call"
     || instr_str == "pop"
     || instr_str == "dec"
     || instr_str == "jnz"
     || instr_str == "ret"
     || instr_str == "sahf"
     || instr_str == "ja"
     || instr_str == "movsx"
     || instr_str == "xor"
     || instr_str == "js"
     || instr_str == "jg"
     || instr_str == "jz"
     || instr_str == "jnc"
     || instr_str == "shr"
     || instr_str == "jge"
     || instr_str == "je"
     || instr_str == "jle"
     || instr_str == "movzx"
     || instr_str == "shrd"
     || instr_str == "adc"
     || instr_str == "shld"
     || instr_str == "div"
     || instr_str == "jl"

     || instr_str == "sal"
     || instr_str == "sar"
     || instr_str == "bswap"
     || instr_str == "setae"

     || instr_str == "jecxz"
     || instr_str == "test"
     || instr_str == "and"
     || instr_str == "jno"
     || instr_str == "jc"
     || instr_str == "xchg"
     || instr_str == "cld"
     || instr_str == "int"

     || instr_str == "enter"
     || instr_str == "leave"
     || instr_str == "pushad"
     || instr_str == "popad"

     || instr_str == "jnge"

     || instr_str == "jna"

     || instr_str == "jng"

     || instr_str == "rol"
       )
    {
        return true;
    }
    return false;
}

bool is_x87_instruction(string instr_str)
{
    if (instr_str == "fild"
     || instr_str == "fdivp"
     || instr_str == "fstp"
     || instr_str == "fadd"
     || instr_str == "fld"
     || instr_str == "fmul"
     || instr_str == "fld1"
     || instr_str == "fsub"
     || instr_str == "fsubrp"
     || instr_str == "faddp"
     || instr_str == "fchs"
     || instr_str == "fsubr"
     || instr_str == "fldz"
     || instr_str == "fcom"
     || instr_str == "fstsw"
     || instr_str == "fsqrt"
     || instr_str == "fst"
     || instr_str == "fxch"
     || instr_str == "fpatan"
     || instr_str == "fsin"
     || instr_str == "fdiv"
     || instr_str == "ffree"
     || instr_str == "fscale"
     || instr_str == "fdivr"
     || instr_str == "fmulp"
     || instr_str == "fsubp"
     || instr_str == "fldpi"
     || instr_str == "fcos"
     || instr_str == "fsincos"
     || instr_str == "fcompp"
     || instr_str == "ftst"
     || instr_str == "fcomp"
     || instr_str == "fiadd"
     || instr_str == "fistp"
     || instr_str == "frndint"
     || instr_str == "fist"
     || instr_str == "fisub"
     || instr_str == "fdivrp"

     || instr_str == "fptan"
     || instr_str == "ficomp"
     || instr_str == "fabs"
     || instr_str == "fimul"

     || instr_str == "fidiv"
     || instr_str == "fnstsw"
       )
    {
        return true;
    }
    return false;
}


void read_procedure_file(string filename)
{
    scope File fd;
    char[] buf;
    asm_proc *cur_proc = null;
    asm_file *cur_file = null;
    string procfilename = "";

    try {
        fd.open(filename);

        while (fd.readln(buf))
        {
            // remove return from end of the line
            while (buf.length > 0 && (buf[buf.length - 1] == '\r' || buf[buf.length - 1] == '\n'))
            {
                buf.length--;
            }

            if (buf.length == 0) continue;

            long colon = buf.indexOf(':');
            if (colon == -1)
            {
                stderr.writeln("Error reading procedure line: " ~ buf.idup);
                exit(1);
            }

            string linetype = buf[0..colon].strip().idup;
            buf = buf[colon+1..$].strip();

            switch(linetype)
            {
                case "file":
                    long index = buf.indexOf('[');

                    if (index >= 0)
                    {
                        procfilename = buf[0..index].strip().idup;
                        buf = buf[index+1..buf.indexOf(']')].strip();
                    }
                    else
                    {
                        procfilename = buf.idup;
                        buf.length = 0;
                    }

                    files.length++;
                    cur_file = &(files[files.length - 1]);
                    cur_file.name = procfilename;

                    switch (buf)
                    {
                        case "":
                            cur_file.rounding_mode = FPU_RC.NONE;
                            break;
                        case "fpu_round_nearest":
                            cur_file.rounding_mode = FPU_RC.NEAREST;
                            break;
                        case "fpu_round_up":
                            cur_file.rounding_mode = FPU_RC.UP;
                            break;
                        default:
                            stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                            exit(1);
                    }

                    cur_proc = null;
                    break;
                case "procedure":
                    procedures.length++;
                    cur_proc = &(procedures[procedures.length - 1]);
                    cur_proc.filename = procfilename;

                    long index = buf.indexOf('[');

                    if (index >= 0)
                    {
                        cur_proc.name = buf[0..index].strip().idup;
                        buf = buf[index+1..buf.indexOf(']')].strip();
                    }
                    else
                    {
                        cur_proc.name = buf.idup;
                        buf.length = 0;
                    }

                    cur_proc.public_proc = false;
                    cur_proc.rounding_mode = FPU_RC.NONE;
                    cur_proc.fpureg_datatype = FPU_DT.NONE;

                    if (buf != "")
                    {
                        auto parts = str_split_strip(buf.idup, ',');

                        foreach (part; parts)
                        {
                            switch (part)
                            {
                                case "public":
                                    cur_proc.public_proc = true;
                                    break;
                                case "fpu_round_nearest":
                                    cur_proc.rounding_mode = FPU_RC.NEAREST;
                                    break;
                                case "fpu_round_up":
                                    cur_proc.rounding_mode = FPU_RC.UP;
                                    break;
                                case "fpu_use_floats":
                                    cur_proc.fpureg_datatype = FPU_DT.FLOAT;
                                    break;
                                default:
                                    stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                                    exit(1);
                            }
                        }
                    }

                    break;
                case "arguments":
                    auto arguments = str_split_strip(buf.idup, ',');
                    foreach (argument; arguments)
                    {
                        long index = argument.indexOf('[');
                        string argparam;

                        if (index >= 0)
                        {
                            argparam = argument[index+1..argument.indexOf(']')].strip();
                            argument = argument[0..index].strip();
                        }
                        else
                        {
                            argparam = "";
                        }

                        cur_proc.arguments.length++;
                        asm_proc_param *cur_param = &(cur_proc.arguments[cur_proc.arguments.length - 1]);

                        cur_param.name = argument.idup;
                        switch (argparam)
                        {
                            case "":
                            case "input":
                                cur_param.input = true;
                                break;
                            case "float":
                                cur_param.input = true;
                                cur_param.floatarg = true;
                                break;
                            case "output":
                                cur_param.output = true;
                                break;
                            case "input-output":
                                cur_param.input = true;
                                cur_param.output = true;
                                break;
                            default:
                                stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                                exit(1);
                        }

                        if (is_register(argument))
                        {
                            cur_param.type = PPT.register;
                            if (cur_param.input)
                            {
                                cur_proc.input_regs_list[argument] = true;
                            }
                            if (cur_param.output)
                            {
                                cur_proc.output_regs_list[argument] = true;
                            }
                        }
                        else if (is_fpu_register(argument) || is_fpu_register2(argument))
                        {
                            cur_param.type = PPT.fpu_reg;

                            cur_param.fpuindex = to!byte(argument[argument.indexOf('(')+1..argument.indexOf(')')]);
                            if (cur_param.fpuindex >= 0)
                            {
                                if (cur_param.input)
                                {
                                    cur_proc.input_fpu_regs_list[-cur_param.fpuindex] = true;
                                }
                                if (cur_param.output)
                                {
                                    cur_proc.output_fpu_regs_list[-cur_param.fpuindex] = true;
                                }
                            }
                            else
                            {
                                if (cur_param.input || !cur_param.output || (cur_param.fpuindex < 0 && cur_proc.fpu_index < 0))
                                {
                                    stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                                    exit(1);
                                }

                                if (cur_proc.fpu_index < -cur_param.fpuindex)
                                {
                                    cur_proc.fpu_index = -cur_param.fpuindex;
                                }
                            }
                        }
                        else
                        {
                            cur_param.type = PPT.variable;
                        }
                    }

                    break;
                case "return register":
                    cur_proc.return_reg = buf.idup;
                    if (!is_register(cur_proc.return_reg))
                    {
                        stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                        exit(1);
                    }
                    cur_proc.scratch_regs_list[cur_proc.return_reg] = true;
                    break;
                case "scratch registers":
                    auto regs = str_split_strip(buf.idup, ',');
                    foreach (reg; regs)
                    {
                        if (!is_register(reg))
                        {
                            stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                            exit(1);
                        }

                        cur_proc.scratch_regs_list[reg] = true;
                    }
                    break;
                case "scratch fpu registers":
                    auto fpu_regs = str_split_strip(buf.idup, ',');
                    foreach (fpu_reg; fpu_regs)
                    {
                        if (!is_fpu_register(fpu_reg))
                        {
                            stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                            exit(1);
                        }

                        byte fpuindex = to!byte(fpu_reg[fpu_reg.indexOf('(')+1..fpu_reg.indexOf(')')]);

                        if (fpuindex < 0)
                        {
                            stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                            exit(1);
                        }

                        cur_proc.scratch_fpu_regs_list[-fpuindex] = true;
                    }
                    break;
                case "decrease fpu pointer":
                    if (!is_number(buf.idup) || cur_proc.fpu_index > 0)
                    {
                        stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                        exit(1);
                    }
                    cur_proc.fpu_index = - to!int(buf);
                    break;
                default:
                    stderr.writeln("Error reading procedure line: " ~ linetype ~ ": " ~ buf.idup);
                    exit(1);
            }
        }

    } catch (Exception e) {
        stderr.writeln(e.toString());
        exit(1);
    } finally {
        fd.close();
    }
}

void read_input_file(string filename)
{
    scope File fd;
    char[] buf;
    uint numlines, maxlines;

    current_file_name = filename;

    current_input_file = null;
    foreach (i, ref f; files)
    {
        if (f.name == current_file_name)
        {
            current_input_file = &files[i];
            break;
        }
    }

    try {
        fd.open(filename);

        fd.seek(0, SEEK_END);
        ulong filesize = fd.tell;
        fd.seek(0);

        maxlines = cast(uint)(filesize / 25);
        numlines = 0;

        lines.length = maxlines;

        while (fd.readln(buf))
        {
            numlines ++;
            if (numlines > maxlines)
            {
                maxlines += 100;
                lines.length = maxlines;
            }

            // remove return from end of the line
            while (buf.length > 0 && (buf[buf.length - 1] == '\r' || buf[buf.length - 1] == '\n'))
            {
                buf.length--;
            }
            lines[numlines - 1].orig = buf.idup;

            // remove line comment, remove whitespace from start and end of line, replace tabs with spaces, remove duplicate spaces
            long position = buf.indexOf(';');
            if (position >= 0)
            {
                lines[numlines - 1].comment = buf[position+1..$].idup;
                if (lines[numlines - 1].comment.length >= 1 && lines[numlines - 1].comment[0] == '/')
                {
                    lines[numlines - 1].comment = " " ~ lines[numlines - 1].comment;
                }
                buf.length = position;
            }
            else
            {
                lines[numlines - 1].comment = "".idup;
            }
            buf = buf.strip().detab(1).squeeze([' ']);
            lines[numlines - 1].line = buf.idup;

            // extract first and second word in lowercase
            buf = buf.toLower();
            position = buf.indexOf(' ');
            if (position >= 0)
            {
                lines[numlines - 1].word[0] = buf[0..position].idup;
                buf = buf[position+1..$];

                position = buf.indexOf(' ');
                if (position >= 0)
                {
                    lines[numlines - 1].word[1] = buf[0..position].idup;
                    buf = buf[position+1..$];
                }
                else
                {
                    lines[numlines - 1].word[1] = buf.idup;
                }
            }
            else
            {
                lines[numlines - 1].word[0] = buf.idup;
                lines[numlines - 1].word[1] = "".idup;
            }
        }

        if (maxlines < numlines + maximum_lookahead)
        {
            lines.length = numlines + maximum_lookahead;
        }

        foreach (uint i; numlines..numlines + maximum_lookahead)
        {
            lines[i].orig = "".idup;
            lines[i].line = "".idup;
            lines[i].comment = "".idup;
            lines[i].word[0] = "".idup;
            lines[i].word[1] = "".idup;
        }
    } catch (Exception e) {
        stderr.writeln(e.toString());
        exit(1);
    } finally {
        fd.close();
    }

    output_lines.length = numlines;
}

void add_output_line(string output_line)
{
    uint index = cast(uint)output_lines[current_line].length;
    output_lines[current_line].length++;
    output_lines[current_line][index] = output_line.idup;
}

void write_output_file(string filename)
{
    scope File fd;

    try {
        fd.open(filename, "wt");

        foreach (i, ol; output_lines)
        {
            if (i >= current_line)
            {
                break;
            }


            if (lines[i].comment != "")
            {
                if (ol.length > 0 && ol[0] != "")
                {
                    fd.writeln(ol[0] ~ " //" ~ lines[i].comment);
                }
                else
                {
                    fd.writeln("//" ~ lines[i].comment);
                }

                foreach(j; 1..ol.length)
                {
                    fd.writeln(ol[j]);
                }
            }
            else
            {
                if (ol.length > 0)
                {
                    foreach (line; ol)
                    {
                        fd.writeln(line);
                    }
                }
                else
                {
                    fd.writeln("");
                }
            }

        }

    } catch (Exception e) {
        stderr.writeln(e.toString());
        exit(1);
    } finally {
        fd.close();
    }
}

void input_error(string errstr)
{
    stdout.writeln(errstr ~ ": " ~ to!string(current_line + 1));
    stdout.writeln(lines[current_line].orig);
    write_output_file("output.cc");
    exit(1);
}

void read_local_variables_arguments(string vars, bool arguments)
{
    int cur_var = (cast(int)local_variables.length) - 1;

    auto split_vars = str_split_strip(vars, ',');

    foreach (cur_index, var; split_vars)
    {
        cur_var ++;
        local_variables.length ++;

        int colonpos = cast(int)var.indexOf(":");

        if (colonpos == -1)
        {
            local_variables[cur_var].name = var.idup;
            var = "";
        }
        else
        {
            local_variables[cur_var].name = var[0..colonpos].stripRight().idup;
            var = var[colonpos + 1..$].stripLeft();
        }

        local_variables[cur_var].linenum = current_line;
        local_variables[cur_var].size = 0;
        local_variables[cur_var].offset = 0;
        local_variables[cur_var].inttype = false;
        local_variables[cur_var].floattype = false;
        local_variables[cur_var].structype = false;
        local_variables[cur_var].argument = arguments;

        colonpos = cast(int)var.indexOf(":");

        if (colonpos > 0)
        {
            string var_type = var[0..colonpos].stripRight();
            var = var[colonpos + 1..$].stripLeft();

            if (var_type.toLower() == "dword")
            {
                try
                {
                    local_variables[cur_var].numitems = to!int(var);
                    local_variables[cur_var].size = 4;
                }
                catch (Exception e)
                {
                    // error
                }
            }
            else if (var_type.toLower() == "byte")
            {
                try
                {
                    local_variables[cur_var].numitems = to!int(var);
                    local_variables[cur_var].size = 1;
                }
                catch (Exception e)
                {
                    if (var.length > 5 && var[0..5] == "size ")
                    {
                        auto var_struc = find_struc(var[5..$]);
                        if (var_struc != null)
                        {
                            local_variables[cur_var].numitems = 1;
                            local_variables[cur_var].size = var_struc.size;
                            local_variables[cur_var].structype = true;
                            local_variables[cur_var].type_name = var_struc.name.idup;
                        }
                    }
                    // else error
                }
            }
        }
        else if (var.toLower() == "dword" || var == "")
        {
            local_variables[cur_var].size = 4;
            local_variables[cur_var].numitems = 1;
        }
        else if (var.toLower() == "byte")
        {
            local_variables[cur_var].size = 1;
            local_variables[cur_var].numitems = 1;
        }


        if (local_variables[cur_var].size == 0)
        {
            input_error("Unknown local variable type");
        }

        if (arguments && current_procedure != null)
        {
            if (current_procedure.arguments.length < cur_index + 1)
            {
                input_error("Wrong procedure parameter");
            }

            if (current_procedure.arguments[cur_index].type != PPT.variable || current_procedure.arguments[cur_index].name != local_variables[cur_var].name)
            {
                input_error("Wrong procedure parameter");
            }

            if (local_variables[cur_var].structype || local_variables[cur_var].size != 4 || local_variables[cur_var].numitems != 1)
            {
                input_error("Unhandled procedure parameter");
            }

            if (current_procedure.arguments[cur_index].floatarg)
            {
                local_variables[cur_var].floattype = true;
            }
        }
    }
}

void read_local_variables(string vars)
{
    read_local_variables_arguments(vars, false);
}

void read_proc_arguments(string args)
{
    read_local_variables_arguments(args, true);
}

void analyze_parameters(string params)
{
    instr_params.length = 0;
    int cur_param = -1;

    auto split_params = str_split_strip(params, ',');

    if (split_params.length > 3)
    {
        input_error("Too many instruction parameters");
    }

    foreach (param; split_params)
    {
        cur_param ++;
        instr_params.length ++;

        int overload_size = 0;
        if (param.length > 2)
        {
            if (param[0..2] == "b ")
            {
                overload_size = 1;
                param = param[2..$];
            }
            else if (param[0..2] == "w ")
            {
                overload_size = 2;
                param = param[2..$];
            }
            else if (param[0..2] == "d ")
            {
                overload_size = 4;
                param = param[2..$];
            }
            else if (param.length > 9)
            {
                if (param[0..8].toLower() == "byte ptr")
                {
                    overload_size = 1;
                    param = param[8..$].stripLeft();
                }
                else if (param[0..8].toLower() == "word ptr")
                {
                    overload_size = 2;
                    param = param[8..$].stripLeft();
                }
                else if (param.length > 10 && param[0..9].toLower() == "dword ptr")
                {
                    overload_size = 4;
                    param = param[9..$].stripLeft();
                }
            }
        }
        instr_params[cur_param].paramstr = param.idup;

        if (param == "esp" || param == "sp")
        {
            input_error("esp instruction parameters are not supported");
        }

        if (param == "eax" || param == "ebx" || param == "ecx" || param == "edx" || param == "esi" || param == "edi")
        {
            instr_params[cur_param].type = PT.register;
            instr_params[cur_param].size = 4;
        }
        else if (param == "ax" || param == "bx" || param == "cx" || param == "dx" || param == "si" || param == "di")
        {
            instr_params[cur_param].type = PT.register;
            instr_params[cur_param].size = 2;
        }
        else if (param == "al" || param == "ah" || param == "bl" || param == "bh" || param == "cl" || param == "ch" || param == "dl" || param == "dh")
        {
            instr_params[cur_param].type = PT.register;
            instr_params[cur_param].size = 1;
        }
        else if (param == "ebp")
        {
            instr_params[cur_param].type = PT.reg_ebp;
            instr_params[cur_param].size = 4;
        }
        else if (param == "bp")
        {
            instr_params[cur_param].type = PT.reg_ebp;
            instr_params[cur_param].size = 2;
        }
        else if (param == "st" || is_fpu_register(param))
        {
            instr_params[cur_param].type = PT.fpu_reg;
            instr_params[cur_param].size = 8;

            if (param == "st")
            {
                instr_params[cur_param].paramstr = "st(0)".idup;
            }
        }
        else if (is_register4_list(param))
        {
            auto regs = str_split_strip(param, ' ');

            foreach (regnum; 0..regs.length)
            {
                instr_params[cur_param].paramstr = regs[regnum].idup;
                instr_params[cur_param].type = (regs[regnum] == "ebp")?PT.register:PT.reg_ebp;
                instr_params[cur_param].size = 4;

                if (regnum < regs.length - 1)
                {
                    cur_param ++;
                    instr_params.length ++;
                }
            }
        }
        else if (param.indexOf('[') >= 0)
        {
            instr_params[cur_param].type = PT.memory;
            instr_params[cur_param].size = 0;


            string prefix = param[0..param.indexOf('[')].stripRight();
            param = param[param.indexOf('[') + 1..$];
            string postfix = param[param.indexOf(']') + 1..$].stripLeft();
            param = param[0..param.indexOf(']')].strip();

            if (prefix == "" && postfix.indexOf('[') >= 0)
            {
                prefix = postfix[0..postfix.indexOf('[')].stripRight();
                string param2 = postfix[postfix.indexOf('[') + 1..$];
                postfix = param2[param2.indexOf(']') + 1..$].stripLeft();
                param2 = param2[0..param2.indexOf(']')].strip();

                if (prefix[0] == '.')
                {
                    prefix = prefix[1..$];
                }

                if (param.indexOf('+') == -1 && param.indexOf('-') == -1)
                {
                    param = param ~ "+" ~ param2;
                }
                else
                {
                    if (param2.indexOf('+') == -1 && param2.indexOf('-') == -1)
                    {
                        param = param2 ~ "+" ~ param;
                    }
                    else
                    {
                        param = param ~ "+" ~ param2;
                    }
                }
            }

            instr_params[cur_param].base = "".idup;
            instr_params[cur_param].index = "".idup;
            instr_params[cur_param].displacement = "".idup;
            instr_params[cur_param].index_mult = 0;
            instr_params[cur_param].isstructref = false;

            if (prefix.indexOf("ds:") != -1)
            {
                long index = prefix.indexOf("ds:");
                prefix = (prefix[0..index] ~ prefix[index+3..$]).strip();
            }
            if (prefix.indexOf("ss:") != -1)
            {
                long index = prefix.indexOf("ss:");
                prefix = (prefix[0..index] ~ prefix[index+3..$]).strip();
            }

            bool mem_error = false;

            if (param == "esp")
            {
                param = "";
                instr_params[cur_param].paramstr = "0".idup;
                instr_params[cur_param].type = PT.stack_variable;
            }

            while (param != "")
            {
                if (is_constant_expression(param))
                {
                    if (instr_params[cur_param].displacement == "")
                    {
                        instr_params[cur_param].displacement = param.idup;
                    }
                    else
                    {
                        if (instr_params[cur_param].displacement[0] == '-')
                        {
                            instr_params[cur_param].displacement = "(" ~ instr_params[cur_param].displacement ~ ") + " ~ param;
                        }
                        else
                        {
                            instr_params[cur_param].displacement = instr_params[cur_param].displacement ~ " + " ~ param;
                        }
                    }

                    break;
                }

                int pluspos = cast(int)param.indexOf('+');
                int minuspos = cast(int)param.indexOf('-');
                if (pluspos != -1 && minuspos != -1)
                {
                    if (minuspos > pluspos)
                    {
                        minuspos = -1;
                    }
                    else
                    {
                        pluspos = -1;
                    }
                }

                string mreg;

                if (minuspos != -1)
                {
                    mreg = param[0..minuspos].stripRight();

                    if (is_constant_expression(param[minuspos+1..$].stripLeft()))
                    {
                        if (instr_params[cur_param].displacement == "")
                        {
                            instr_params[cur_param].displacement = param[minuspos..$].idup;
                        }
                        else
                        {
                            mem_error = true;
                        }
                    }
                    else
                    {
                        mem_error = true;
                    }

                    param = "";
                }
                else
                {
                    if (pluspos == -1)
                    {
                        mreg = param;
                        param = "";
                    }
                    else
                    {
                        mreg = param[0..pluspos].stripRight();
                        param = param[pluspos+1..$].stripLeft();
                    }
                }


                if (is_constant_expression(mreg))
                {
                    if (instr_params[cur_param].displacement == "")
                    {
                        instr_params[cur_param].displacement = mreg.idup;
                    }
                    else
                    {
                        if (instr_params[cur_param].displacement[0] == '-')
                        {
                            instr_params[cur_param].displacement = "(" ~ instr_params[cur_param].displacement ~ ") + " ~ mreg;
                        }
                        else
                        {
                            instr_params[cur_param].displacement = instr_params[cur_param].displacement ~ " + " ~ mreg;
                        }
                    }
                }
                else
                {
                    auto parts = str_split_strip(mreg, '*');
                    if (parts.length == 1)
                    {
                        if (is_register4_list(mreg))
                        {
                            if (instr_params[cur_param].base == "")
                            {
                                instr_params[cur_param].base = mreg.idup;
                            }
                            else if (instr_params[cur_param].index == "")
                            {
                                instr_params[cur_param].index = mreg.idup;
                                instr_params[cur_param].index_mult = 1;
                            }
                            else
                            {
                                mem_error = true;
                            }
                        }
                        else
                        {
                            mem_error = true;
                        }
                    }
                    else if (parts.length == 2)
                    {
                        if (is_register4_list(parts[0]))
                        {
                            if (instr_params[cur_param].index == "")
                            {
                                instr_params[cur_param].index = parts[0].idup;

                                instr_params[cur_param].index_mult = to!int(parts[1]);
                            }
                            else
                            {
                                mem_error = true;
                            }
                        }
                        else if (is_register4_list(parts[1]))
                        {
                            if (instr_params[cur_param].index == "")
                            {
                                instr_params[cur_param].index = parts[1].idup;

                                instr_params[cur_param].index_mult = to!int(parts[0]);
                            }
                            else
                            {
                                mem_error = true;
                            }
                        }
                        else
                        {
                            mem_error = true;
                        }
                    }
                    else
                    {
                        mem_error = true;
                    }
                }

            }

            if (instr_params[cur_param].type == PT.memory && instr_params[cur_param].base == "" && instr_params[cur_param].index == "" && instr_params[cur_param].displacement == "")
            {
                mem_error = true;
            }

            if (mem_error)
            {
                input_error("Unknown memory parameter (1)");
            }


            if (prefix != "" && postfix != "")
            {
                if (postfix[0] == '.')
                {
                    auto struct_def = find_struc_by_ref(prefix ~ postfix);
                    if (struct_def != null)
                    {
                        instr_params[cur_param].isstructref = true;
                        instr_params[cur_param].struct_name = struct_def.name.idup;
                        instr_params[cur_param].struct_ref = prefix ~ postfix;
                    }
                    else
                    {
                        mem_error = true;
                    }
                }
                else
                {
                    mem_error = true;
                }
            }
            else if (prefix != "")
            {
                auto struct_def = find_struc_by_ref(prefix);
                if (struct_def != null)
                {
                    instr_params[cur_param].isstructref = true;
                    instr_params[cur_param].struct_name = struct_def.name.idup;
                    instr_params[cur_param].struct_ref = prefix.idup;
                }
                else
                {
                    PT var_type;
                    auto var_def = find_local_variable(prefix);
                    if (var_def != null) var_type = PT.local_variable;

                    if (var_def == null)
                    {
                        var_def = find_variable(prefix);
                        if (var_def != null) var_type = PT.variable;
                    }

                    if (var_def == null)
                    {
                        var_def = find_local_struct_variable(prefix);
                        if (var_def != null) var_type = PT.local_struc_variable;
                    }

                    if (var_def == null)
                    {
                        var_def = find_struct_variable(prefix);
                        if (var_def != null) var_type = PT.struc_variable;
                    }

                    if (var_def != null)
                    {
                        if (var_def.numitems != 1 && !var_def.structype)
                        {
                            instr_params[cur_param].isvariablearray = true;
                            instr_params[cur_param].var_type = var_type;
                            if (var_type == PT.struc_variable)
                            {
                                instr_params[cur_param].var_name = get_struct_variable_reference(prefix);
                            }
                            else
                            {
                                instr_params[cur_param].var_name = prefix.idup;
                            }
                        }
                        else if (var_def.numitems == 1 && instr_params[cur_param].base == "" && instr_params[cur_param].index == "" && instr_params[cur_param].displacement != "" && is_number(instr_params[cur_param].displacement) && var_type == PT.local_variable)
                        {
                            instr_params[cur_param].type = PT.displaced_local_variable;
                            instr_params[cur_param].paramstr = prefix.idup;
                        }
                        else
                        {
                            mem_error = true;
                        }
                    }
                    else
                    {
                        mem_error = true;
                    }
                }
            }
            else if (postfix != "")
            {
                if (postfix[0] == '.')
                {
                    auto struct_def = find_struc_by_ref(postfix[1..$]);
                    if (struct_def != null)
                    {
                        instr_params[cur_param].isstructref = true;
                        instr_params[cur_param].struct_name = struct_def.name.idup;
                        instr_params[cur_param].struct_ref = postfix[1..$].idup;
                    }
                    else
                    {
                        PT var_type;
                        auto var_def = find_local_variable(postfix[1..$]);
                        if (var_def != null) var_type = PT.local_variable;

                        if (var_def == null)
                        {
                            var_def = find_variable(postfix[1..$]);
                            if (var_def != null) var_type = PT.variable;
                        }

                        if (var_def == null)
                        {
                            var_def = find_local_struct_variable(postfix[1..$]);
                            if (var_def != null) var_type = PT.local_struc_variable;
                        }

                        if (var_def == null)
                        {
                            var_def = find_struct_variable(postfix[1..$]);
                            if (var_def != null) var_type = PT.struc_variable;
                        }

                        if (var_def != null)
                        {
                            if (var_def.numitems != 1 && !var_def.structype)
                            {
                                instr_params[cur_param].isvariablearray = true;
                                instr_params[cur_param].var_type = var_type;
                                if (var_type == PT.struc_variable)
                                {
                                    instr_params[cur_param].var_name = get_struct_variable_reference(postfix[1..$]);
                                }
                                else
                                {
                                    instr_params[cur_param].var_name = postfix[1..$].idup;
                                }
                            }
                            else if (var_def.numitems == 1 && instr_params[cur_param].base == "" && instr_params[cur_param].index == "" && instr_params[cur_param].displacement != "" && is_number(instr_params[cur_param].displacement) && var_type == PT.local_variable)
                            {
                                instr_params[cur_param].type = PT.displaced_local_variable;
                                instr_params[cur_param].paramstr = postfix[1..$].idup;
                            }
                            else
                            {
                                mem_error = true;
                            }
                        }
                        else
                        {
                            mem_error = true;
                        }
                    }
                }
                else
                {
                    mem_error = true;
                }
            }

            if (mem_error)
            {
                input_error("Unknown memory parameter (2)");
            }

            if (overload_size > 0)
            {
                instr_params[cur_param].size = overload_size;
            }
            else if (instr_params[cur_param].type == PT.stack_variable)
            {
                instr_params[cur_param].size = 4;
            }
            else if (instr_params[cur_param].isstructref)
            {
                auto var = find_struct_variable_by_ref(instr_params[cur_param].struct_name, instr_params[cur_param].struct_ref);
                if (var != null)
                {
                    if (!var.structype)
                    {
                        if (var.numitems != 0)
                        {
                            instr_params[cur_param].size = var.size;
                        }
                        else
                        {
                            auto struct_def = find_struc_with_var(var.name);
                            foreach (i, v; struct_def.vars)
                            {
                                if (v.offset == var.offset && v.numitems != 0)
                                {
                                    instr_params[cur_param].size = v.size;
                                    break;
                                }
                            }

                            if (instr_params[cur_param].size == 0)
                            {
                                mem_error = true;
                            }
                            //else if (instr_params[cur_param].index_mult != 0 && instr_params[cur_param].index_mult != instr_params[cur_param].size)
                            //{
                            //    mem_error = true;
                            //}
                        }
                    }
                    else
                    {
                        instr_params[cur_param].size = get_common_struct_variables_size(var.type_name);
                    }
                }
                else
                {
                    mem_error = true;
                }
            }
            else if (instr_params[cur_param].isvariablearray)
            {
                asm_var *var;
                if (instr_params[cur_param].var_type == PT.local_struc_variable)
                {
                    var = find_local_struct_variable(instr_params[cur_param].var_name);
                }
                else if (instr_params[cur_param].var_type == PT.struc_variable)
                {
                    var = find_struct_variable(instr_params[cur_param].var_name);
                }
                else if (instr_params[cur_param].var_type == PT.local_variable)
                {
                    var = find_local_variable(instr_params[cur_param].var_name);
                }
                else
                {
                    var = find_variable(instr_params[cur_param].var_name);
                }

                instr_params[cur_param].size = var.size;
            }

            if (mem_error)
            {
                input_error("Unknown memory parameter (3)");
            }
        }
        else if (find_local_variable(param) != null)
        {
            auto var = find_local_variable(param);

            instr_params[cur_param].type = PT.local_variable;
            instr_params[cur_param].size = (overload_size == 0)?var.size:overload_size;
        }
        else if (find_variable(param) != null)
        {
            auto var = find_variable(param);

            instr_params[cur_param].type = PT.variable;
            instr_params[cur_param].size = (overload_size == 0)?var.size:overload_size;
        }
        else if (find_local_struct_variable(param) != null)
        {
            auto var = find_local_struct_variable(param);

            instr_params[cur_param].type = PT.local_struc_variable;
            instr_params[cur_param].size = (overload_size == 0)?var.size:overload_size;
        }
        else if (find_struct_variable(param) != null)
        {
            auto var = find_struct_variable(param);

            instr_params[cur_param].paramstr = get_struct_variable_reference(param);

            instr_params[cur_param].type = PT.struc_variable;
            instr_params[cur_param].size = (overload_size == 0)?var.size:overload_size;
        }
        else if (is_constant_expression(param))
        {
            instr_params[cur_param].type = PT.constant;
            instr_params[cur_param].size = 0;
        }
        else if (is_struc_var_offset(param))
        {
            instr_params[cur_param].type = PT.struc_var_offset;
            instr_params[cur_param].size = 0;
            instr_params[cur_param].paramstr = param[param.indexOf(' ')+1..$].idup;
        }
        else if (find_proc(param) != null)
        {
            instr_params[cur_param].type = PT.procedure_address;
            instr_params[cur_param].size = 4;
        }
        else if (param.length > 2 && param[0..2] == "@@")
        {
            instr_params[cur_param].type = PT.local_label;
            instr_params[cur_param].size = 0;
        }


        if (instr_params[cur_param].type == PT.none)
        {
            input_error("Unknown parameter");
        }
    }
}

void consolidate_parameters_size(ref instruction_parameter param1, ref instruction_parameter param2)
{
    if (param1.size == 0 && param2.size == 0)
    {
        input_error("unknown parameters size");
    }

    if (param1.size == 0)
    {
        param1.size = param2.size;
    }
    else if (param2.size == 0)
    {
        param2.size = param1.size;
    }
    else if (param1.size != param2.size)
    {
        input_error("different parameters size");
    }
}

string convert_constant_expression_to_c(string expr)
{
    string last_delim = "";
    string res = "".idup;

    while (expr != "")
    {
        int nextpos = -1;
        string next_delim = "";
        foreach (c; "+-*/()")
        {
            int pos = cast(int)expr.indexOf(c);
            if (pos != -1)
            {
                if (nextpos == -1 || nextpos > pos)
                {
                    nextpos = pos;

                    char[1] delim_char = [c];
                    next_delim = delim_char.idup;
                }
            }
        }

        int shlpos = cast(int)expr.indexOf(" shl ");
        int shrpos = cast(int)expr.indexOf(" shr ");
        int shiftpos;
        string shift_delim = "";
        if (shlpos != -1)
        {
            if (shrpos != -1)
            {
                if (shrpos < shlpos)
                {
                    shiftpos = shrpos;
                    shift_delim = ">>";
                }
                else
                {
                    shiftpos = shlpos;
                    shift_delim = "<<";
                }
            }
            else
            {
                shiftpos = shlpos;
                shift_delim = "<<";
            }
        }
        else
        {
            shiftpos = shrpos;
            if (shrpos != -1)
            {
                shift_delim = ">>";
            }
        }


        res = res ~ ((last_delim == "(")?"":" ") ~ last_delim ~ ((last_delim == ")")?"":" ");

        string expr_part;

        if (nextpos == -1 && shiftpos == -1)
        {
            expr_part = expr;
            expr = "";
            last_delim = "";
        }
        else if (shiftpos == -1 || (nextpos != -1 && nextpos < shiftpos))
        {
            expr_part = expr[0..nextpos].stripRight();
            expr = expr[nextpos + 1..$].stripLeft();
            last_delim = next_delim;
        }
        else
        {
            expr_part = expr[0..shiftpos].stripRight();
            expr = expr[shiftpos + 5..$].stripLeft();
            last_delim = shift_delim;
        }

        if (expr_part == "")
        {
            // ok
        }
        else if (find_constant(expr_part) != null)
        {
            // ok
            res = res ~ expr_part;
        }
        else if (expr_part.length > 5 && expr_part[0..5] == "size " && find_struc(expr_part[5..$]) != null)
        {
            // ok
            res = res ~ "sizeof(" ~ expr_part[5..$] ~ ")";
        }
        else if (is_number(expr_part))
        {
            // ok
            if (expr_part[expr_part.length-1] == 'h')
            {
                res = res ~ "0x" ~ expr_part[0..expr_part.length-1];
            }
            else
            {
                res = res ~ expr_part;
            }
        }
        else
        {
            input_error("bad constant conversion to c");
        }
    }

    res = res ~ " " ~ last_delim;

    return res.strip();
}

string get_fpu_reg_string(int stnum, uint flags)
{
    int fpu_index = current_state.fpu_index - stnum;

    if (fpu_index > current_state.fpu_max_index)
    {
        current_state.fpu_max_index = fpu_index;
    }
    if (fpu_index < current_state.fpu_min_index)
    {
        current_state.fpu_min_index = fpu_index;
    }

    if (fpu_index < 10)
    {
        int index = 9 - fpu_index;
        if (index + 1 > cast(int)(current_state.fpu_regs.length))
        {
            int orig_index = cast(int)(current_state.fpu_regs.length);
            current_state.fpu_regs.length = index + 1;
            foreach (i; orig_index..index + 1)
            {
                asm_fpu_reg fpu_reg;
                fpu_reg.read = false;
                fpu_reg.write = false;
                fpu_reg.read_unknown = false;
                current_state.fpu_regs[i] = fpu_reg;
            }
        }

        if ((flags & FF.read) && !current_state.fpu_regs[index].write && !current_state.fpu_regs[index].read)
        {
            current_state.fpu_regs[index].read_unknown = true;
        }
        if (flags & FF.read)
        {
            current_state.fpu_regs[index].read = true;
        }
        if (flags & FF.write)
        {
            current_state.fpu_regs[index].write = true;
        }
    }

    return "fpu_reg".idup ~ to!string(fpu_index);
}

string get_displacement_struct_index_str(string displacement, string struct_name)
{
    if (displacement == "size " ~ struct_name || displacement == "(size " ~ struct_name ~ ")")
    {
        return "1".idup;
    }
    if (displacement == "-size " ~ struct_name)
    {
        return "-1".idup;
    }

    auto parts = str_split_strip(displacement, '*');

    if (parts.length == 1 && find_constant(parts[0]) != null)
    {
        auto c = find_constant(parts[0]);

        if (c.value == "size " ~ struct_name || c.value == "(size " ~ struct_name ~ ")")
        {
            return "1".idup;
        }
        if (c.value == "-size " ~ struct_name)
        {
            return "-1".idup;
        }
    }
    else if (parts.length == 2 && find_constant(parts[0]) != null && is_number(parts[1]))
    {
        auto c = find_constant(parts[0]);
        int mult = to!int(parts[1]);

        if (c.value == "size " ~ struct_name || c.value == "(size " ~ struct_name ~ ")")
        {
            return to!string(mult);
        }
        if (c.value == "-size " ~ struct_name)
        {
            return to!string(-mult);
        }
    }
    else if (parts.length == 2 && (parts[1] == "size " ~ struct_name || parts[1] == "(size " ~ struct_name ~ ")") && is_constant_expression(parts[0]))
    {
        return convert_constant_expression_to_c(parts[0]);
    }

    return "".idup;
}

int get_displacement_multiply_index(string displacement, int mult)
{
    auto parts = str_split_strip(displacement, '*');

    if (parts.length == 1)
    {
        if (is_number(parts[0]))
        {
            int num = get_number_value(parts[0]);
            if (num % mult == 0)
            {
                return num / mult;
            }
        }
        else if (parts[0][0] == '-' && is_number(parts[0][1..$]))
        {
            int num = get_number_value(parts[0][1..$]);
            if (num % mult == 0)
            {
                return -(num / mult);
            }
        }
    }
    else if (parts.length == 2)
    {
        if (is_number(parts[0]) && is_number(parts[1]))
        {
            if (get_number_value(parts[0]) == mult)
            {
                return get_number_value(parts[1]);
            }
            else if (get_number_value(parts[1]) == mult)
            {
                return get_number_value(parts[0]);
            }
        }
        else if (parts[0][0] == '-' && is_number(parts[0][1..$]) && is_number(parts[1]))
        {
            if (get_number_value(parts[0][1..$]) == mult)
            {
                return - get_number_value(parts[1]);
            }
            else if (get_number_value(parts[1]) == mult)
            {
                return - get_number_value(parts[0][1..$]);
            }
        }
    }

    return 0;
}

string get_parameter_read_string(instruction_parameter param, uint flags)
{
    if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 4) && ((flags & ~PF.signed) == 0))
    {
        current_state.regs[param.paramstr].used = true;
        if (!register_has_unknown_value(param.paramstr))
        {
            if (flags & PF.signed)
            {
                return "( (int32_t)".idup ~ param.paramstr ~ " )";
            }
            else
            {
                return param.paramstr.idup;
            }
        }
        else
        {
            current_state.regs[param.paramstr].read_unknown = true;
            return "( 0 /*".idup ~ param.paramstr ~ "*/ )";
        }
    }
    else if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 2) && ((flags & ~PF.signed) == 0))
    {
        string reg32 = "e" ~ param.paramstr;

        current_state.regs[reg32].used = true;
        if (!register_has_unknown_value(reg32))
        {
            return "( (".idup ~ ((flags & PF.signed)?"int16_t":"uint16_t") ~ ")" ~ reg32 ~ " )";
        }
        else
        {
            current_state.regs[reg32].read_unknown = true;
            return "( 0 /*".idup ~ param.paramstr ~ "*/ )";
        }
    }
    else if ((param.type == PT.register) && (param.size == 1) && ((flags & ~PF.signed) == 0))
    {
        string reg32 = "e" ~ param.paramstr[0..1] ~ "x";

        current_state.regs[reg32].used = true;
        if (!register_has_unknown_value(reg32))
        {
            return "( (".idup ~ ((flags & PF.signed)?"int8_t":"uint8_t") ~ ")" ~ ((param.paramstr[1] == 'l')?reg32:"(" ~ reg32 ~ " >> 8)") ~ " )";
        }
        else
        {
            current_state.regs[reg32].read_unknown = true;
            return "( 0 /*".idup ~ param.paramstr ~ "*/ )";
        }
    }
    else if ((param.type == PT.fpu_reg) && (flags == PF.floattype))
    {
        return get_fpu_reg_string(to!int(param.paramstr[param.paramstr.indexOf('(')+1..param.paramstr.indexOf(')')]), FF.read);
    }
    else if (param.type == PT.local_variable || param.type == PT.variable || param.type == PT.local_struc_variable || param.type == PT.struc_variable)
    {
        asm_var *var;
        if (param.type == PT.local_struc_variable)
        {
            var = find_local_struct_variable(param.paramstr);
        }
        else if (param.type == PT.struc_variable)
        {
            var = find_struct_variable(param.paramstr);
        }
        else if (param.type == PT.local_variable)
        {
            var = find_local_variable(param.paramstr);
        }
        else
        {
            var = find_variable(param.paramstr);
        }

        if ((param.size == 4) && ((flags & ~PF.signed) == 0))
        {
            if (!var.floattype && !var.structype && var.size == param.size && var.numitems == 1)
            {
                var.inttype = true;

                if (flags & PF.signed)
                {
                    return "( (int32_t)".idup ~ param.paramstr ~ " )";
                }
                else
                {
                    return param.paramstr.idup;
                }
            }
            else if (var.floattype && !var.structype && var.size == param.size && var.numitems == 1)
            {
                return "( *((".idup ~ ((flags & PF.signed)?"int32_t":"uint32_t") ~ " *)&" ~ param.paramstr ~ ") )";
            }
            else
            {
                input_error("unhandled variable parameter for reading");
            }
        }
        else if ((param.size == 2) && ((flags & ~PF.signed) == 0))
        {
            if (var.inttype && !var.floattype && !var.structype && var.size == 4 && var.numitems == 1)
            {
                if (flags & PF.signed)
                {
                    return "( (int16_t)".idup ~ param.paramstr ~ " )";
                }
                else
                {
                    return "( (uint16_t)".idup ~ param.paramstr ~ " )";
                }
            }
            else
            {
                input_error("unhandled variable parameter for reading");
            }
        }
        else if ((param.size == 1) && ((flags & ~PF.signed) == 0))
        {
            if (!var.floattype && !var.structype && var.size == 4 && var.numitems == 1)
            {
                var.inttype = true;

                if (flags & PF.signed)
                {
                    return "( (int8_t)".idup ~ param.paramstr ~ " )";
                }
                else
                {
                    return "( (uint8_t)".idup ~ param.paramstr ~ " )";
                }
            }
            else if (!var.floattype && !var.structype && var.size == param.size && var.numitems == 1)
            {
                var.inttype = true;

                if (flags & PF.signed)
                {
                    return "( (int8_t)".idup ~ param.paramstr ~ " )";
                }
                else
                {
                    return param.paramstr.idup;
                }
            }
            else
            {
                input_error("unhandled variable parameter for reading");
            }
        }
        else if ((param.size == 4) && (flags == PF.floattype))
        {
            if (!var.inttype && !var.structype && var.size == param.size && var.numitems == 1)
            {
                var.floattype = true;

                return param.paramstr.idup;
            }
            else
            {
                input_error("unhandled variable parameter for reading");
            }
        }
        else if (flags == PF.addressof)
        {
            if (var.structype && var.numitems == 1)
            {
                return "( (uint32_t)&(".idup ~ param.paramstr ~ ") )";
            }
            else if (!var.structype && var.numitems != 1)
            {
                return "( (uint32_t)&(".idup ~ param.paramstr ~ "[0]) )";
            }
            else
            {
                input_error("unhandled variable parameter for reading");
            }
        }
        else
        {
            input_error("unhandled variable parameter for reading");
        }
    }
    else if ((param.type == PT.displaced_local_variable) && (param.size == 1) && ((flags & ~PF.signed) == 0))
    {
        auto var = find_local_variable(param.paramstr);

        if (var.inttype && !var.floattype && !var.structype && var.size == 4 && var.numitems == 1)
        {
            int displacement = to!int(param.displacement);

            if (flags & PF.signed)
            {
                return "( (int8_t)(".idup ~ param.paramstr ~ " >> " ~ to!string(8 * displacement) ~ ") )";
            }
            else
            {
                return "( (uint8_t)(".idup ~ param.paramstr ~ " >> " ~ to!string(8 * displacement) ~ ") )";
            }
        }
        else
        {
            input_error("unhandled variable parameter for reading");
        }
    }
    else if ((param.type == PT.memory) && ((flags & ~(PF.signed | PF.addressof | PF.floattype)) == 0))
    {
        if (param.base != "")
        {
            current_state.regs[param.base].used = true;
            if (register_has_unknown_value(param.base))
            {
                current_state.regs[param.base].read_unknown = true;
            }
        }
        if (param.index != "")
        {
            current_state.regs[param.index].used = true;
            if (register_has_unknown_value(param.index))
            {
                current_state.regs[param.index].read_unknown = true;
            }
        }

        if (!param.isstructref && !param.isvariablearray)
        {
            string res = param.base.idup;
            string resindex = "".idup;

            if (!(flags & PF.addressof) && param.base != "" && param.index_mult != 1 && (param.index == "" || param.index_mult == param.size) && (param.displacement == "" || get_displacement_multiply_index(param.displacement, param.size) != 0))
            {
                if (param.index != "")
                {
                    if (resindex != "") resindex = resindex ~ " + ";
                    resindex = resindex ~ param.index;
                }

                if (param.displacement != "")
                {
                    if (resindex != "") resindex = resindex ~ " + ";
                    resindex = resindex ~ to!string(get_displacement_multiply_index(param.displacement, param.size));
                }
            }
            else
            {
                if (param.index != "")
                {
                    if (res != "") res = res ~ " + ";
                    res = res ~ param.index;
                    if (param.index_mult != 1)
                    {
                        res = res ~ " * " ~ to!string(param.index_mult);
                    }
                }

                if (param.displacement != "")
                {
                    if (res != "") res = res ~ " + ";
                    res = res ~ "(" ~ convert_constant_expression_to_c(param.displacement) ~ ")";
                }
            }

            if (flags & PF.addressof)
            {
                return "( ".idup ~ res ~ " )";
            }
            else
            {
                string typestr;

                if (flags & PF.floattype)
                {
                    if (param.size == 4)
                    {
                        typestr = "float";
                    }
                    else
                    {
                        input_error("unhandled memory parameter for reading");
                    }
                }
                else if (flags & PF.signed)
                {
                    typestr = "int" ~ to!string(param.size * 8) ~ "_t";
                }
                else
                {
                    typestr = "uint" ~ to!string(param.size * 8) ~ "_t";
                }

                if (resindex != "")
                {
                    return "( ((".idup ~ typestr ~ " *)(" ~ res ~ "))[" ~ resindex ~ "] )";
                }
                else
                {
                    return "( *((".idup ~ typestr ~ " *)(" ~ res ~ ")) )";
                }
            }
        }
        else if (param.base != "" && param.isstructref)
        {
            auto var = find_struct_variable_by_ref(param.struct_name, param.struct_ref);
            string struct_ref = get_struct_variable_reference_by_ref(param.struct_name, param.struct_ref);

            if (((param.index != "" && !var.structype && param.index_mult == var.size) ||
                 (var.structype && get_common_struct_variables_size(var.type_name) != 0 &&
                  (param.index != "" ||
                   (param.displacement != "" && is_number(param.displacement) && (to!int(param.displacement) % get_common_struct_variables_size(var.type_name)) == 0) ||
                   (param.displacement != "" && get_displacement_multiply_index(param.displacement, get_common_struct_variables_size(var.type_name)) != 0)
                  )
                 )
                ) && var.numitems == 1 && param.struct_ref.indexOf('.') == -1
               )
            {
                auto struct_def = find_struc_with_var(var.name);
                int find_size;
                if (!var.structype)
                {
                    find_size = var.size;
                }
                else
                {
                    find_size = get_common_struct_variables_size(var.type_name);
                }

                foreach (i, v; struct_def.vars)
                {
                    if (v.offset == var.offset && v.numitems != 1 && v.size == find_size)
                    {
                        var = &(struct_def.vars[i]);
                        struct_ref = var.name;
                        break;
                    }
                }
            }

            if ( (flags & PF.addressof) ||
                 ( (((flags & PF.floattype) && !var.inttype) || (!(flags & PF.floattype) && !var.floattype)) && !var.structype && var.size == param.size ) ||
                 ( (!(flags & PF.floattype) && !var.floattype) && !var.structype && var.size > param.size )
               )
            {
                if (!(flags & PF.addressof))
                {
                    if (flags & PF.floattype)
                    {
                        var.floattype = true;
                    }
                    else
                    {
                        var.inttype = true;
                    }
                }

                string var_pointer = param.base.idup;
                string struct_index = "".idup;
                string var_index = "".idup;

                if (param.index != "")
                {
                    if (var.numitems != 1 && var.size != 1 && var.size == param.index_mult)
                    {
                        var_index = param.index.idup;
                    }
                    else
                    {
                        var_pointer = var_pointer ~ " + " ~ param.index ~ ((param.index_mult == 1)?"":" * " ~ to!string(param.index_mult));
                    }
                }

                if (param.displacement != "")
                {
                    struct_index = get_displacement_struct_index_str(param.displacement, param.struct_name);
                    if (struct_index == "")
                    {
                        int indexpos = cast(int)struct_ref.indexOf("[0]");
                        if (indexpos >= 0)
                        {
                            string struct_var_name = struct_ref[0..indexpos];
                            auto struct_var_def = find_struct_variable_by_ref(param.struct_name, struct_var_name);
                            string struct_var_index = get_displacement_struct_index_str(param.displacement, struct_var_def.type_name);
                            if (struct_var_index != "")
                            {
                                struct_ref = struct_ref[0..indexpos+1] ~ struct_var_index ~ struct_ref[indexpos+2..$];
                            }
                            else if (param.displacement != "0")
                            {
                                indexpos = -1;
                            }
                        }

                        if (indexpos >= 0)
                        {
                            // done
                        }
                        else if (var.numitems != 1 && var.size != 1 && get_displacement_multiply_index(param.displacement, var.size) != 0)
                        {
                            if (var_index != "") var_index = var_index ~ " + ";
                            var_index = var_index ~ to!string(get_displacement_multiply_index(param.displacement, var.size));
                        }
                        else if (var.numitems != 1 && var.size != 1 && is_number(param.displacement) && (to!int(param.displacement) % var.size) == 0)
                        {
                            int displacement_num = to!int(param.displacement);

                            if (var_index != "") var_index = var_index ~ " + ";
                            var_index = var_index ~ to!string(displacement_num / var.size);
                        }
                        else
                        {
                            var_pointer = var_pointer ~ " + " ~ convert_constant_expression_to_c(param.displacement);
                        }
                    }
                }

                if (var_pointer.indexOf('+') >= 0)
                {
                    var_pointer = "(".idup ~ var_pointer ~ ")";
                }

                if (var_index == "" && var.numitems != 1)
                {
                    var_index = "0".idup;
                }

                string res = "((".idup ~ param.struct_name ~ " *)" ~ var_pointer ~ ")";
                if (struct_index == "")
                {
                    res = res ~ "->";
                }
                else
                {
                    res = res ~ "[" ~ struct_index ~ "].";
                }

                res = res ~ struct_ref;

                if (var_index != "")
                {
                    res = res ~ "[" ~ var_index ~ "]";
                }

                if (flags & PF.addressof)
                {
                    return "( (uint32_t)&(".idup ~ res ~ ") )";
                }
                else if (flags & PF.signed && !(flags & PF.floattype))
                {
                    return "( (int".idup ~ to!string(param.size * 8) ~ "_t)(" ~ res ~ ") )";
                }
                else
                {
                    if (var.size == param.size)
                    {
                        return "( ".idup ~ res ~ " )";
                    }
                    else
                    {
                        return "( (uint".idup ~ to!string(param.size * 8) ~ "_t)(" ~ res ~ ") )";
                    }
                }
            }
            else if ((!(flags & PF.floattype) && var.floattype) && !var.structype && param.size == 4 && var.size == param.size && ((var.numitems == 1) || (param.index != "" && param.index_mult == var.size && var.numitems != 1)))
            {
                string res = param.base.idup;

                if (param.index != "" && var.numitems == 1)
                {
                    res = "(".idup ~ res ~ " + " ~ param.index ~ ((param.index_mult != 1)?" * " ~ to!string(param.index_mult):"") ~ ")";
                }

                if (param.displacement == "")
                {
                    res = "((".idup ~ param.struct_name ~ " *)" ~ res ~ ")->" ~ struct_ref;
                }
                else if (get_displacement_struct_index_str(param.displacement, param.struct_name) != "")
                {
                    res = "((".idup ~ param.struct_name ~ " *)" ~ res ~ ")[" ~ get_displacement_struct_index_str(param.displacement, param.struct_name) ~ "]." ~ struct_ref;
                }
                else
                {
                    input_error("unhandled memory parameter for reading");
                }

                if (param.index != "" && var.numitems != 1)
                {
                    res = res ~ "[" ~ param.index ~ "]";
                }

                return "( *((uint32_t *)&(".idup ~ res ~ ")) )";
            }
            else
            {
                input_error("unhandled memory parameter for reading");
            }
        }
        else if (param.isvariablearray)
        {
            asm_var *var;
            if (param.var_type == PT.local_struc_variable)
            {
                var = find_local_struct_variable(param.var_name);
            }
            else if (param.var_type == PT.struc_variable)
            {
                var = find_struct_variable(param.var_name);
            }
            else if (param.var_type == PT.local_variable)
            {
                var = find_local_variable(param.var_name);
            }
            else
            {
                var = find_variable(param.var_name);
            }

            if ((flags & PF.addressof) ||
                ( (((flags & PF.floattype) && !var.inttype) || (!(flags & PF.floattype) && !var.floattype) || (!(flags & PF.floattype) && var.floattype && param.size == 4)) && var.size == param.size )
               )
            {
                if (!(flags & PF.addressof))
                {
                    if (flags & PF.floattype || !var.floattype)
                    {
                        if (flags & PF.floattype)
                        {
                            var.floattype = true;
                        }
                        else
                        {
                            var.inttype = true;
                        }
                    }
                }

                if ((var.size == 1) || (param.base == "" && (param.index == "" || param.index_mult == var.size) && (param.displacement == "" || param.displacement == "0" || get_displacement_multiply_index(param.displacement, var.size) != 0)))
                {
                    string res = "".idup;
                    if (param.base != "")
                    {
                        if (res != "") res = res ~ " + ";
                        res = res ~ param.base;
                    }
                    if (param.index != "")
                    {
                        if (res != "") res = res ~ " + ";
                        res = res ~ param.index;
                    }
                    if (param.displacement != "")
                    {
                        if (res != "") res = res ~ " + ";
                        if (var.size == 1 || param.displacement == "0")
                        {
                            res = res ~ param.displacement;
                        }
                        else
                        {
                            res = res ~ to!string(get_displacement_multiply_index(param.displacement, var.size));
                        }
                    }

                    if (flags & PF.addressof)
                    {
                        return "( (uint32_t)(&(".idup ~ param.var_name ~ "[" ~ res ~ "])) )";
                    }
                    else if (!(flags & PF.floattype) && var.floattype)
                    {
                        return "( *((uint32_t *)&(".idup ~ param.var_name ~ "[" ~ res ~ "])) )";
                    }
                    else if (flags & PF.signed)
                    {
                        return "( (int".idup ~ to!string(param.size * 8) ~ "_t)(" ~ param.var_name ~ "[" ~ res ~ "]) )";
                    }
                    else
                    {
                        return "( ".idup ~ param.var_name ~ "[" ~ res ~ "] )";
                    }
                }
                else
                {
                    string res = "((uint32_t)&(" ~ param.var_name ~ "[0]))";
                    if (param.base != "")
                    {
                        res = res ~ " + " ~ param.base;
                    }
                    if (param.index != "")
                    {
                        res = res ~ " + " ~ param.index ~ ((param.index_mult != 1)?" * " ~ to!string(param.index_mult):"");
                    }
                    if (param.displacement != "")
                    {
                        res = res ~ " + " ~ param.displacement;
                    }

                    if (flags & PF.addressof)
                    {
                        return "( " ~ res ~ " )";
                    }
                    else
                    {
                        string typestr;
                        if (flags & PF.floattype)
                        {
                            if (param.size == 4)
                            {
                                typestr = "float";
                            }
                            else
                            {
                                input_error("unhandled memory parameter for writing");
                            }
                        }
                        else if (flags & PF.signed)
                        {
                            typestr = "int" ~ to!string(param.size * 8) ~ "_t";
                        }
                        else
                        {
                            typestr = "uint" ~ to!string(param.size * 8) ~ "_t";
                        }

                        return "( *((" ~ typestr ~ " *)(" ~ res ~ ")) )";
                    }
                }
            }
            else
            {
                input_error("unhandled memory parameter for writing");
            }
        }
        else
        {
            input_error("unhandled memory parameter for reading");
        }
    }
    else if ((param.type == PT.stack_variable) && (param.size == 4) && ((flags & ~PF.signed) == 0))
    {
        string res = "stack_var".idup ~ ((current_state.stack_index < 10)?"0":"") ~ to!string(current_state.stack_index);
        if (flags & PF.signed)
        {
            return "((int32_t)".idup ~ res ~ ")";
        }
        else
        {
            return res;
        }
    }
    else if ((param.type == PT.constant) && ((flags & ~PF.signed) == 0))
    {
        return "( ".idup ~ convert_constant_expression_to_c(param.paramstr) ~ " )";
    }
    else if ((param.type == PT.struc_var_offset) && (param.size == 4) && (flags == 0))
    {
        auto struc_def = find_struc_by_ref(param.paramstr);
        return "( offsetof(".idup ~ struc_def.name ~ ", " ~ param.paramstr ~ ") )";
    }
    else if ((param.type == PT.procedure_address) && (flags == PF.addressof))
    {
        return "( (uint32_t)&".idup ~ param.paramstr ~ " )";
    }
    else
    {
        input_error("unhandled parameter for reading");
    }

    return "".idup;
}

string get_parameter_read_string(instruction_parameter param)
{
    return get_parameter_read_string(param, 0);
}

string get_parameter_write_string(instruction_parameter param, uint flags)
{
    if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 4) && (flags == 0))
    {
        current_state.regs[param.paramstr].used = true;
        current_state.regs[param.paramstr].value = "".idup;

        return param.paramstr.idup ~ " = ";
    }
    else if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 2) && (flags == 0))
    {
        string reg32 = "e".idup ~ param.paramstr;
        bool orig_value = register_has_unknown_value(reg32);

        current_state.regs[reg32].used = true;
        current_state.regs[reg32].value = "".idup;

        return reg32 ~ " = " ~ ((orig_value)?"/*":"") ~ "(" ~ reg32 ~ " & 0xffff0000) |" ~ ((orig_value)?"*/":"") ~ " (uint16_t)(";
    }
    else if ((param.type == PT.register) && (param.size == 1) && (flags == 0))
    {
        string reg32 = "e".idup ~ param.paramstr[0..1] ~ "x";
        bool orig_value = register_has_unknown_value(reg32);

        current_state.regs[reg32].used = true;
        current_state.regs[reg32].value = "".idup;

        if (param.paramstr[1] == 'l')
        {
            return reg32 ~ " = " ~ ((orig_value)?"/*":"") ~ "(" ~ reg32 ~ " & 0xffffff00) |" ~ ((orig_value)?"*/":"") ~ " (uint8_t)(";
        }
        else
        {
            return reg32 ~ " = set_high_byte(" ~ ((orig_value)?"0 /*":"") ~ reg32 ~ ((orig_value)?"*/":"") ~ ", ";
        }
    }
    else if ((param.type == PT.fpu_reg) && (flags == PF.floattype))
    {
        return get_fpu_reg_string(to!int(param.paramstr[param.paramstr.indexOf('(')+1..param.paramstr.indexOf(')')]), FF.write) ~ " = ";
    }
    else if ((param.type == PT.local_variable || param.type == PT.variable || param.type == PT.local_struc_variable || param.type == PT.struc_variable) && (flags == 0))
    {
        asm_var *var;
        if (param.type == PT.local_struc_variable)
        {
            var = find_local_struct_variable(param.paramstr);
        }
        else if (param.type == PT.struc_variable)
        {
            var = find_struct_variable(param.paramstr);
        }
        else if (param.type == PT.local_variable)
        {
            var = find_local_variable(param.paramstr);
        }
        else
        {
            var = find_variable(param.paramstr);
        }

        if (!var.floattype && !var.structype && var.size == param.size && var.numitems == 1)
        {
            var.inttype = true;

            return param.paramstr.idup ~ " = " ~ ((param.size == 4)?"":"(");
        }
        else if (var.floattype && !var.structype && param.size == 4 && var.size == param.size && var.numitems == 1)
        {
            return "*((uint32_t *)&(".idup ~ param.paramstr ~ ")) = ";
        }
        else if (var.inttype && var.size == 4 && param.size == 1 && var.numitems == 1)
        {
            return param.paramstr.idup ~ " = (" ~ param.paramstr ~ " & 0xffffff00) | (uint8_t)(";
        }
        else
        {
            input_error("unhandled variable parameter for writing");
        }
    }
    else if ((param.type == PT.local_variable || param.type == PT.variable || param.type == PT.local_struc_variable || param.type == PT.struc_variable) && (param.size == 4) && (flags == PF.floattype))
    {
        asm_var *var;
        if (param.type == PT.local_struc_variable)
        {
            var = find_local_struct_variable(param.paramstr);
        }
        else if (param.type == PT.struc_variable)
        {
            var = find_struct_variable(param.paramstr);
        }
        else if (param.type == PT.local_variable)
        {
            var = find_local_variable(param.paramstr);
        }
        else
        {
            var = find_variable(param.paramstr);
        }

        if (!var.inttype && !var.structype && var.size == param.size && var.numitems == 1)
        {
            var.floattype = true;

            return param.paramstr.idup ~ " = ";
        }
        else
        {
            input_error("unhandled variable parameter for writing");
        }
    }
    else if ((param.type == PT.memory) && ((flags & ~(PF.floattype)) == 0))
    {
        if (param.base != "")
        {
            current_state.regs[param.base].used = true;
            if (register_has_unknown_value(param.base))
            {
                current_state.regs[param.base].read_unknown = true;
            }
        }
        if (param.index != "")
        {
            current_state.regs[param.index].used = true;
            if (register_has_unknown_value(param.index))
            {
                current_state.regs[param.index].read_unknown = true;
            }
        }

        if (!param.isstructref && !param.isvariablearray)
        {
            string res = param.base.idup;
            string resindex = "".idup;

            if (param.base != "" && param.index_mult != 1 && (param.index == "" || param.index_mult == param.size) && (param.displacement == "" || get_displacement_multiply_index(param.displacement, param.size) != 0))
            {
                if (param.index != "")
                {
                    if (resindex != "") resindex = resindex ~ " + ";
                    resindex = resindex ~ param.index;
                }

                if (param.displacement != "")
                {
                    if (resindex != "") resindex = resindex ~ " + ";
                    resindex = resindex ~ to!string(get_displacement_multiply_index(param.displacement, param.size));
                }
            }
            else
            {
                if (param.index != "")
                {
                    if (res != "") res = res ~ " + ";
                    res = res ~ param.index;
                    if (param.index_mult != 1)
                    {
                        res = res ~ " * " ~ to!string(param.index_mult);
                    }
                }

                if (param.displacement != "")
                {
                    if (res != "") res = res ~ " + ";
                    res = res ~ "(" ~ convert_constant_expression_to_c(param.displacement) ~ ")";
                }
            }

            string typestr;
            if (flags & PF.floattype)
            {
                if (param.size == 4)
                {
                    typestr = "float";
                }
                else
                {
                    input_error("unhandled memory parameter for writing");
                }
            }
            else
            {
                typestr = "uint" ~ to!string(param.size * 8) ~ "_t";
            }

            string right_side = "".idup;
            if (param.size < 4)
            {
                right_side = "(uint".idup ~ to!string(param.size * 8) ~ "_t) (";
            }

            if (resindex != "")
            {
                return "((".idup ~ typestr ~ " *)(" ~ res ~ "))[" ~ resindex ~ "] = " ~ right_side;
            }
            else
            {
                return "*((".idup ~ typestr ~ " *)(" ~ res ~ ")) = " ~ right_side;
            }
        }
        else if (param.base != "" && param.isstructref)
        {
            auto var = find_struct_variable_by_ref(param.struct_name, param.struct_ref);
            string struct_ref = get_struct_variable_reference_by_ref(param.struct_name, param.struct_ref);

            if (param.index != "" && ((!var.structype && param.index_mult == var.size) || (var.structype && get_common_struct_variables_size(var.type_name) != 0)) && var.numitems == 1 && param.struct_ref.indexOf('.') == -1)
            {
                auto struct_def = find_struc_with_var(var.name);
                int find_size;
                if (!var.structype)
                {
                    find_size = var.size;
                }
                else
                {
                    find_size = get_common_struct_variables_size(var.type_name);
                }

                foreach (i, v; struct_def.vars)
                {
                    if (v.offset == var.offset && v.numitems != 1 && v.size == find_size)
                    {
                        var = &(struct_def.vars[i]);
                        struct_ref = var.name;
                        break;
                    }
                }
            }

            if ((((flags & PF.floattype) && !var.inttype) || (!(flags & PF.floattype) && !var.floattype)) && !var.structype && var.size == param.size)
            {
                if (flags & PF.floattype)
                {
                    var.floattype = true;
                }
                else
                {
                    var.inttype = true;
                }

                string var_pointer = param.base.idup;
                string struct_index = "".idup;
                string var_index = "".idup;

                if (param.index != "")
                {
                    if (var.numitems != 1 && var.size != 1 && var.size == param.index_mult)
                    {
                        var_index = param.index.idup;
                    }
                    else
                    {
                        var_pointer = var_pointer ~ " + " ~ param.index ~ ((param.index_mult == 1)?"":" * " ~ to!string(param.index_mult));
                    }
                }

                if (param.displacement != "")
                {
                    struct_index = get_displacement_struct_index_str(param.displacement, param.struct_name);
                    if (struct_index == "")
                    {
                        int indexpos = cast(int)struct_ref.indexOf("[0]");
                        if (indexpos >= 0)
                        {
                            string struct_var_name = struct_ref[0..indexpos];
                            auto struct_var_def = find_struct_variable_by_ref(param.struct_name, struct_var_name);
                            string struct_var_index = get_displacement_struct_index_str(param.displacement, struct_var_def.type_name);
                            if (struct_var_index != "")
                            {
                                struct_ref = struct_ref[0..indexpos+1] ~ struct_var_index ~ struct_ref[indexpos+2..$];
                            }
                            else if (param.displacement != "0")
                            {
                                indexpos = -1;
                            }
                        }

                        if (indexpos >= 0)
                        {
                            // done
                        }
                        else if (var.numitems != 1 && var.size != 1 && get_displacement_multiply_index(param.displacement, param.size) != 0)
                        {
                            if (var_index != "")
                            {
                                var_index = var_index ~ " + ";
                            }
                            var_index = var_index ~ to!string(get_displacement_multiply_index(param.displacement, param.size));
                        }
                        else if (var.numitems != 1 && var.size != 1 && is_number(param.displacement) && (to!int(param.displacement) % var.size) == 0)
                        {
                            int displacement_num = to!int(param.displacement);

                            if (var_index != "")
                            {
                                var_index = var_index ~ " + ";
                            }
                            var_index = var_index ~ to!string(displacement_num / var.size);
                        }
                        else
                        {
                            var_pointer = var_pointer ~ " + " ~ convert_constant_expression_to_c(param.displacement);
                        }
                    }
                }

                if (var_pointer.indexOf('+') >= 0)
                {
                    var_pointer = "(".idup ~ var_pointer ~ ")";
                }

                if (var_index == "" && var.numitems != 1)
                {
                    var_index = "0".idup;
                }

                string res = "((".idup ~ param.struct_name ~ " *)" ~ var_pointer ~ ")";
                if (struct_index == "")
                {
                    res = res ~ "->";
                }
                else
                {
                    res = res ~ "[" ~ struct_index ~ "].";
                }

                res = res ~ struct_ref;

                if (var_index != "")
                {
                    res = res ~ "[" ~ var_index ~ "]";
                }

                return res ~ " = " ~ ((param.size < 4)?"(uint" ~ to!string(param.size * 8) ~ "_t) (":"");
            }
            else if ((!(flags & PF.floattype) && var.floattype) && !var.structype && param.size == 4 && var.size == param.size && ((param.index == "" && var.numitems == 1) || (param.index != "" && param.index_mult == var.size && var.numitems != 1)))
            {
                string res = param.base.idup;
                if (param.displacement == "")
                {
                    res = "((".idup ~ param.struct_name ~ " *)" ~ res ~ ")->" ~ struct_ref;
                }
                else if (get_displacement_struct_index_str(param.displacement, param.struct_name) != "")
                {
                    res = "((".idup ~ param.struct_name ~ " *)" ~ res ~ ")[" ~ get_displacement_struct_index_str(param.displacement, param.struct_name) ~ "]." ~ struct_ref;
                }
                else
                {
                    input_error("unhandled memory parameter for reading");
                }

                if (param.index != "")
                {
                    res = res ~ "[" ~ param.index ~ "]";
                }

                return "*((uint32_t *)&(".idup ~ res ~ ")) = ";
            }
            else
            {
                input_error("unhandled memory parameter for writing");
            }
        }
        else if (param.isvariablearray)
        {
            asm_var *var;
            if (param.var_type == PT.local_struc_variable)
            {
                var = find_local_struct_variable(param.var_name);
            }
            else if (param.var_type == PT.struc_variable)
            {
                var = find_struct_variable(param.var_name);
            }
            else if (param.var_type == PT.local_variable)
            {
                var = find_local_variable(param.var_name);
            }
            else
            {
                var = find_variable(param.var_name);
            }

            if ((((flags & PF.floattype) && !var.inttype) || (!(flags & PF.floattype) && !var.floattype) || (!(flags & PF.floattype) && var.floattype && param.size == 4)) && var.size == param.size)
            {
                if (flags & PF.floattype || !var.floattype)
                {
                    if (flags & PF.floattype)
                    {
                        var.floattype = true;
                    }
                    else
                    {
                        var.inttype = true;
                    }
                }

                if ((var.size == 1) || (param.base == "" && (param.index == "" || param.index_mult == var.size) && (param.displacement == "" || param.displacement == "0" || get_displacement_multiply_index(param.displacement, var.size) != 0)))
                {
                    string res = "".idup;
                    if (param.base != "")
                    {
                        if (res != "") res = res ~ " + ";
                        res = res ~ param.base;
                    }
                    if (param.index != "")
                    {
                        if (res != "") res = res ~ " + ";
                        res = res ~ param.index;
                    }
                    if (param.displacement != "")
                    {
                        if (res != "") res = res ~ " + ";
                        if (var.size == 1 || param.displacement == "0")
                        {
                            res = res ~ param.displacement;
                        }
                        else
                        {
                            res = res ~ to!string(get_displacement_multiply_index(param.displacement, var.size));
                        }
                    }

                    string right_side = "";
                    if (param.size < 4)
                    {
                        right_side = "(uint" ~ to!string(param.size * 8) ~ "_t) (";
                    }

                    if (!(flags & PF.floattype) && var.floattype)
                    {
                        return "*((uint32_t *)&(".idup ~ param.var_name ~ "[" ~ res ~ "])) = " ~ right_side;
                    }
                    else
                    {
                        return param.var_name.idup ~ "[" ~ res ~ "] = " ~ right_side;
                    }
                }
                else
                {
                    string res = "((uint32_t)&(".idup ~ param.var_name ~ "[0]))";
                    if (param.base != "")
                    {
                        res = res ~ " + " ~ param.base;
                    }
                    if (param.index != "")
                    {
                        res = res ~ " + " ~ param.index ~ ((param.index_mult != 1)?" * " ~ to!string(param.index_mult):"");
                    }
                    if (param.displacement != "")
                    {
                        res = res ~ " + " ~ param.displacement;
                    }

                    string typestr;
                    if (flags & PF.floattype)
                    {
                        if (param.size == 4)
                        {
                            typestr = "float";
                        }
                        else
                        {
                            input_error("unhandled memory parameter for writing");
                        }
                    }
                    else
                    {
                        typestr = "uint" ~ to!string(param.size * 8) ~ "_t";
                    }

                    string right_side = "";
                    if (param.size < 4)
                    {
                        right_side = "(uint" ~ to!string(param.size * 8) ~ "_t) (";
                    }

                    return "*((".idup ~ typestr ~ " *)(" ~ res ~ ")) = " ~ right_side;
                }
            }
            else
            {
                input_error("unhandled memory parameter for writing");
            }
        }
        else
        {
            input_error("unhandled memory parameter for writing");
        }
    }
    else if ((param.type == PT.stack_variable) && (param.size == 4) && (flags == 0))
    {
        return "stack_var".idup ~ ((current_state.stack_index < 10)?"0":"") ~ to!string(current_state.stack_index) ~ " = ";
    }
    else
    {
        input_error("unhandled parameter for writing");
    }

    return "".idup;
}

string get_parameter_write_string(instruction_parameter param)
{
    return get_parameter_write_string(param, 0);
}

void define_local_label(string labelname, uint linenum, bool label_after_jmp)
{
    auto cur_label = find_local_label(labelname);

    if (cur_label == null)
    {
        uint cur_index = cast(uint)local_labels.length;

        local_labels.length++;
        local_labels[cur_index].name = labelname.idup;
        local_labels[cur_index].linenum = linenum;
        local_labels[cur_index].state = current_state;

        return;
    }

    if (cur_label.state.stack_index != current_state.stack_index)
    {
        input_error("different label stack index");
    }
    if (cur_label.state.fpu_index != current_state.fpu_index)
    {
        input_error("different label fpu index: " ~ to!string(cur_label.state.fpu_index) ~ " != " ~ to!string(current_state.fpu_index));
    }

    if (cur_label.state.fpu_max_index > current_state.fpu_max_index)
    {
        current_state.fpu_max_index = cur_label.state.fpu_max_index;
    }
    else if (cur_label.state.fpu_max_index < current_state.fpu_max_index)
    {
        cur_label.state.fpu_max_index = current_state.fpu_max_index;
    }

    uint fpu_min_length = cast(uint)( (cur_label.state.fpu_regs.length < current_state.fpu_regs.length)?cur_label.state.fpu_regs.length:current_state.fpu_regs.length );

    if (fpu_min_length > 0)
    {
        foreach (index; 0..fpu_min_length)
        {
            // todo: label after jump ???
            cur_label.state.fpu_regs[index].read |= current_state.fpu_regs[index].read;
            cur_label.state.fpu_regs[index].write |= current_state.fpu_regs[index].write;
            cur_label.state.fpu_regs[index].read_unknown |= current_state.fpu_regs[index].read_unknown;

            if (linenum != 0) // label definition
            {
                current_state.fpu_regs[index].read = cur_label.state.fpu_regs[index].read;
                current_state.fpu_regs[index].write = cur_label.state.fpu_regs[index].write;
                current_state.fpu_regs[index].read_unknown = cur_label.state.fpu_regs[index].read_unknown;
            }
        }
    }

    if (cur_label.state.fpu_regs.length < current_state.fpu_regs.length)
    {
        uint orig_length = cast(uint)cur_label.state.fpu_regs.length;
        cur_label.state.fpu_regs.length = current_state.fpu_regs.length;
        foreach (index; orig_length..cur_label.state.fpu_regs.length)
        {
            // todo: label after jump ???
            cur_label.state.fpu_regs[index] = current_state.fpu_regs[index];
        }
        cur_label.state.fpu_min_index = current_state.fpu_min_index;
    }
    else if (current_state.fpu_regs.length < cur_label.state.fpu_regs.length && linenum != 0)
    {
        uint orig_length = cast(uint)current_state.fpu_regs.length;
        current_state.fpu_regs.length = cur_label.state.fpu_regs.length;
        foreach (index; orig_length..current_state.fpu_regs.length)
        {
            current_state.fpu_regs[index] = cur_label.state.fpu_regs[index];
        }
        current_state.fpu_min_index = cur_label.state.fpu_min_index;
    }

    foreach (ref reg; cur_label.state.regs)
    {
        if (current_state.regs[reg.name].used)
        {
            reg.used = true;
        }
        else if (reg.used && linenum != 0)
        {
            current_state.regs[reg.name].used = true;
        }

        if (reg.value != current_state.regs[reg.name].value)
        {
            // todo: label after jump ???
            reg.value = "".idup;
            if (linenum != 0) // label definition
            {
                current_state.regs[reg.name].value = "".idup;
            }
        }
    }

    int stack_max_index = (cur_label.state.stack_max_index < current_state.stack_max_index)?cur_label.state.stack_max_index:current_state.stack_max_index;

    if (stack_max_index >= 0)
    {
        foreach (index; 0..stack_max_index+1)
        {
            if (cur_label.state.stack_value[index] != current_state.stack_value[index])
            {
                // todo: label after jump ???
                cur_label.state.stack_value[index] = "".idup;
                if (linenum != 0) // label definition
                {
                    current_state.stack_value[index] = "".idup;
                }
            }
        }
    }

    if (cur_label.state.stack_max_index < current_state.stack_max_index)
    {
        cur_label.state.stack_value.length = current_state.stack_max_index + 1;
        foreach (index; cur_label.state.stack_max_index+1..current_state.stack_max_index+1)
        {
            cur_label.state.stack_value[index] = "".idup;
        }
        cur_label.state.stack_max_index = current_state.stack_max_index;
    }
    else if (current_state.stack_max_index < cur_label.state.stack_max_index && linenum != 0)
    {
        current_state.stack_value.length = cur_label.state.stack_max_index + 1;
        foreach (index; current_state.stack_max_index+1..cur_label.state.stack_max_index+1)
        {
            current_state.stack_value[index] = "".idup;
        }
        current_state.stack_max_index = cur_label.state.stack_max_index;
    }

    if (linenum != 0)
    {
        cur_label.linenum = linenum;
    }
}

void process_input_file()
{
    current_line = 0;
    uint maxlines = cast(uint)lines.length - maximum_lookahead;
    inputline line;
    asm_struc *cur_struc;
    asm_var *cur_var;
    asm_const *cur_const;
    bool in_struc = false;
    bool in_proc = false;

    struct structure_stack {
        uint size, maxsize;
        bool isunion;
    };
    structure_stack[] struc_stack;

    struc_stack.length = 0;

    while (current_line < maxlines)
    {
        line = lines[current_line];

        // empty lines or only comments
        if (line.line == "")
        {
            current_line++;
            continue;
        }

        // multiline comment
        if (line.line == "comment #" || line.line == "comment &")
        {
            string endcomment = line.line[8..9];

            add_output_line("#if 0");
            if (line.orig[line.orig.indexOf(endcomment[0]) + 1..$] != "")
            {
                add_output_line("//" ~ line.orig[line.orig.indexOf(endcomment[0]) + 1..$]);
            }
            lines[current_line].comment = "".idup;

            current_line++;
            while ((current_line < maxlines) && (lines[current_line].line != endcomment))
            {
                add_output_line("//" ~ lines[current_line].orig);
                lines[current_line].comment = "".idup;
                current_line++;
            };

            if (current_line < maxlines)
            {
                add_output_line("#endif");
                current_line++;
            }
            continue;
        }

        if (line.word[0] == "if")
        {
            input_error("Conditional compilation is not supported");
        }

        if (in_struc)
        {
            // end of structure definition
            if (line.line == "ends")
            {
                if (struc_stack.length == 0)
                {
                    cur_struc = null;
                    in_struc = false;
                }
                else
                {
                    int stack_index = cast(int)struc_stack.length - 1;

                    if (!cur_struc.isunion)
                    {
                        struc_stack[stack_index].maxsize = cur_struc.size - struc_stack[stack_index].size;
                    }

                    if (struc_stack[stack_index].isunion)
                    {
                        if (stack_index > 0)
                        {
                            if (struc_stack[stack_index].maxsize > struc_stack[stack_index - 1].maxsize)
                            {
                                struc_stack[stack_index - 1].maxsize = struc_stack[stack_index].maxsize;
                            }
                        }

                        cur_struc.size = struc_stack[stack_index].size;
                    }
                    else
                    {
                        cur_struc.size = struc_stack[stack_index].size + struc_stack[stack_index].maxsize;
                    }

                    cur_struc.isunion = struc_stack[stack_index].isunion;

                    struc_stack.length--;
                }
                current_line++;
                continue;
            }

            // struc label definition
            if (line.word[1] == "label")
            {
                cur_struc.vars.length++;
                cur_var = &cur_struc.vars[cur_struc.vars.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.offset = cur_struc.size;
                cur_var.numitems = 0;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = false;

                if (substr_from_entry_equal(line.line, 2, ' ', "dword"))
                {
                    cur_var.size = 4;
                    cur_var = null;
                    current_line++;
                    continue;
                }
                else if (substr_from_entry_equal(line.line, 2, ' ', "float"))
                {
                    cur_var.floattype = true;
                    cur_var.size = 4;
                    cur_var = null;
                    current_line++;
                    continue;
                }

                input_error("Unknown struc label definition");
            }

            // struc variable definition
            if (line.word[1] == "float" || line.word[1] == "dd" || line.word[1] == "dw" || line.word[1] == "db")
            {
                cur_struc.vars.length++;
                cur_var = &cur_struc.vars[cur_struc.vars.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.offset = cur_struc.size;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = false;

                if (line.word[1] == "float")
                {
                    cur_var.floattype = true;
                    cur_var.size = 4;
                }
                else if (line.word[1] == "dd")
                {
                    cur_var.size = 4;
                }
                else if (line.word[1] == "dw")
                {
                    cur_var.size = 2;
                }
                else
                {
                    cur_var.size = 1;
                }

                if (substr_from_entry_equal(line.line, 2, ' ', "?"))
                {
                    cur_var.numitems = 1;
                }
                else if (substr_from_entry_equal(line.line, 2, ' ', "?, ?"))
                {
                    cur_var.numitems = 2;
                }
                else if (substr_from_entry_equal(line.line, 2, ' ', "?,?,?"))
                {
                    cur_var.numitems = 3;
                }
                else if (substr_from_entry_equal(line.line, 3, ' ', "dup(?)"))
                {
                    try
                    {
                        cur_var.numitems = to!int(str_entry(line.line, 2, ' '));
                    }
                    catch (Exception e)
                    {
                        cur_var.numitems = 2;
                        // ignore, for now?
                    }
                }
                else
                {
                    input_error("Unknown struc variable definition");
                }

                if (!cur_struc.isunion)
                {
                    cur_struc.size += cur_var.size * cur_var.numitems;
                }
                else if (struc_stack.length != 0)
                {
                    int stack_index = cast(int)struc_stack.length - 1;
                    int var_size = cur_var.size * cur_var.numitems;
                    if (var_size > struc_stack[stack_index].maxsize)
                    {
                        struc_stack[stack_index].maxsize = var_size;
                    }
                }

                cur_var = null;

                current_line++;
                continue;

            }

            // struc variable struc definition
            if (line.word[1] != "" && find_struc(line.line[line.word[0].length+1..line.word[0].length+1+line.word[1].length])) // line.word[1]
            {
                auto var_struct = find_struc(line.line[line.word[0].length+1..line.word[0].length+1+line.word[1].length]);

                cur_struc.vars.length++;
                cur_var = &cur_struc.vars[cur_struc.vars.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.size = var_struct.size;
                cur_var.offset = cur_struc.size;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = true;
                cur_var.type_name = var_struct.name.idup;

                if (substr_from_entry_equal(line.line, 2, ' ', "?"))
                {
                    cur_var.numitems = 1;
                }
                else if (substr_from_entry_equal(line.line, 3, ' ', "dup(?)"))
                {
                    try
                    {
                        cur_var.numitems = to!int(str_entry(line.line, 2, ' '));
                    }
                    catch (Exception e)
                    {
                        cur_var.numitems = 2;
                        // ignore, for now?
                    }
                }
                else
                {
                    input_error("Unknown struc variable struc definition");
                }

                if (!cur_struc.isunion)
                {
                    cur_struc.size += cur_var.size * cur_var.numitems;
                }
                else if (struc_stack.length != 0)
                {
                    int stack_index = cast(int)struc_stack.length - 1;
                    int var_size = cur_var.size * cur_var.numitems;
                    if (var_size > struc_stack[stack_index].maxsize)
                    {
                        struc_stack[stack_index].maxsize = var_size;
                    }
                }

                cur_var = null;

                current_line++;
                continue;
            }

            // anonymous structure or union
            if (line.word[0] == "struc" || line.word[0] == "union")
            {
                int stack_index = cast(int)struc_stack.length;
                struc_stack.length++;

                struc_stack[stack_index].size = cur_struc.size;
                struc_stack[stack_index].maxsize = 0;
                struc_stack[stack_index].isunion = cur_struc.isunion;

                cur_struc.isunion = (line.word[0] == "union");

                current_line++;
                continue;
            }
        }
        else if (in_proc)
        {
            // end of procedure definition
            if (line.line == "endp")
            {
                input_error("unexpected endp");
            }

            // end of procedure definition
            if (line.word[1] == "endp")
            {
                input_error("unexpected endp");
            }

            // arguments definition
            if (line.word[0] == "arg")
            {
                read_proc_arguments(substr_from_entry(line.line, 1, ' '));

                current_line++;
                continue;
            }

            // local variables definition
            if (line.word[0] == "local")
            {
                read_local_variables(substr_from_entry(line.line, 1, ' '));

                current_line++;
                continue;
            }

            // local label
            if (line.line[0..2] == "@@" && line.word[0][line.word[0].length-1..$] == ":")
            {
                define_local_label(line.line[2..line.line.indexOf(':')], current_line, lines[current_line - 1].word[0] == "jmp");
                add_output_line(procedure_name ~ "_" ~ line.line[2..line.line.indexOf(':')+1]);

                if (substr_from_entry_equal(line.line, 1, ' ', ""))
                {
                    current_line++;
                    continue;
                }

                line.line = line.line[line.line.indexOf(' ')+1..$];
                line.word[0] = line.word[1];
                if (line.word[0].length == line.line.length)
                {
                    line.word[1] = "".idup;
                }
                else if (line.word[1] != "")
                {
                    int position = cast(int)line.line[line.word[0].length+1..$].indexOf(' ');
                    if (position != -1)
                    {
                        position += cast(int)line.word[0].length+1;
                        line.word[1] = line.line[line.word[0].length+1..position].toLower().idup;
                    }
                }

                if (line.word[0] == "jmp")
                {
                    input_error("Unconditional jump must not be on the same line as label");
                }
            }
            else if (line.line[0..2] == "@@" && line.word[0].indexOf(":") > 0)
            {
                define_local_label(line.line[2..line.line.indexOf(':')], current_line, lines[current_line - 1].word[0] == "jmp");
                add_output_line(procedure_name ~ "_" ~ line.line[2..line.line.indexOf(':')+1]);

                line.line = line.line[line.line.indexOf(':')+1..$];
                line.word[0] = line.word[0][line.word[0].indexOf(':')+1..$];

                if (line.word[0] == "jmp")
                {
                    input_error("Unconditional jump must not be on the same line as label");
                }
            }
            else if (line.word[0][line.word[0].length-1..$] == ":")
            {
                input_error("Global labels are not supported");
            }

            if (is_instruction_prefix(line.word[0]))
            {
                switch (line.word[0])
                {
                    case "rep":
                        if (line.word[1] == "movsd")
                        {
                            current_state.regs["esi"].used = true;
                            if (register_has_unknown_value("esi"))
                            {
                                current_state.regs["esi"].read_unknown = true;
                            }
                            current_state.regs["esi"].value = "".idup;

                            current_state.regs["edi"].used = true;
                            if (register_has_unknown_value("edi"))
                            {
                                current_state.regs["edi"].read_unknown = true;
                            }
                            current_state.regs["edi"].value = "".idup;

                            current_state.regs["ecx"].used = true;
                            if (register_has_unknown_value("ecx"))
                            {
                                current_state.regs["ecx"].read_unknown = true;
                            }
                            current_state.regs["ecx"].value = "".idup;

                            add_output_line("\tfor (; ecx != 0; ecx--, esi+=4, edi+=4) *(uint32_t *)edi = *(uint32_t *)esi;");
                        }
                        else if (line.word[1] == "stosd" || line.word[1] == "stosb")
                        {
                            current_state.regs["eax"].used = true;
                            if (register_has_unknown_value("eax"))
                            {
                                current_state.regs["eax"].read_unknown = true;
                            }

                            current_state.regs["edi"].used = true;
                            if (register_has_unknown_value("edi"))
                            {
                                current_state.regs["edi"].read_unknown = true;
                            }
                            current_state.regs["edi"].value = "".idup;

                            current_state.regs["ecx"].used = true;
                            if (register_has_unknown_value("ecx"))
                            {
                                current_state.regs["ecx"].read_unknown = true;
                            }
                            current_state.regs["ecx"].value = "".idup;

                            if (line.word[1] == "stosd")
                            {
                                add_output_line("\tfor (; ecx != 0; ecx--, edi+=4) *(uint32_t *)edi = eax;");
                            }
                            else
                            {
                                add_output_line("\tfor (; ecx != 0; ecx--, edi++) *(uint8_t *)edi = (uint8_t)eax;");
                            }
                        }
                        else
                        {
                            input_error("unhandled rep instruction");
                        }

                        break;
                    default:
                        input_error("unhandled prefix instruction");
                        break;
                }

                current_line++;
                continue;
            }

            if (is_x86_instruction(line.word[0]))
            {
                if (line.word[0] != "call")
                {
                    analyze_parameters(substr_from_entry(line.line, 1, ' '));
                }

                switch (line.word[0])
                {
                    case "add":
                    case "sub":
                        string op_string;
                        uint op_flags = 0;

                        switch (line.word[0])
                        {
                            case "add":
                                op_string = "+";
                                break;
                            case "sub":
                                op_string = "-";
                                if (lines[current_line + 1].word[0] == "js" || lines[current_line + 1].word[0] == "jns" || lines[current_line + 1].word[0] == "jz" || lines[current_line + 1].word[0] == "jnz" ||
                                    lines[current_line + 1].word[0] == "jg" || lines[current_line + 1].word[0] == "jge" || lines[current_line + 1].word[0] == "jl" || lines[current_line + 1].word[0] == "jle"
                                   )
                                {
                                    op_flags = PF.signed;
                                }
                                break;
                            default:
                                input_error("unhandled arithmetic instruction");
                                break;
                        }

                        consolidate_parameters_size(instr_params[0], instr_params[1]);
                        string param1str = get_parameter_read_string(instr_params[0], op_flags);
                        string param2str = get_parameter_read_string(instr_params[1], op_flags);
                        string right_side = param1str ~ " " ~ op_string ~ " " ~ param2str;
                        string blockstr = "";
                        if (line.word[0] == "add" && (lines[current_line + 1].word[0] == "adc" || lines[current_line + 1].word[0] == "jc" || lines[current_line + 1].word[0] == "jnc"))
                        {
                            blockstr = "{ uint32_t carry = (UINT" ~ to!string(instr_params[0].size * 8) ~ "_MAX - " ~ param1str ~ " < " ~ param2str ~ ")?1:0; ";
                        }
                        else if (line.word[0] == "sub" && (lines[current_line + 1].word[0] == "jc" || lines[current_line + 1].word[0] == "jnc"))
                        {
                            blockstr = "{ uint32_t carry = (" ~ param1str ~ " < " ~ param2str ~ ")?1:0; ";
                        }
                        add_output_line("\t" ~ blockstr ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ((instr_params[0].size == 4)?"":")") ~ ";");

                        break;
                    case "adc":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);

                        if (lines[current_line - 1].word[0] == "add")
                        {
                            string right_side = get_parameter_read_string(instr_params[0]) ~ " + " ~ get_parameter_read_string(instr_params[1]) ~ " + carry";

                            add_output_line("\t  " ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ((instr_params[0].size == 4)?"":")") ~ "; }");
                        }
                        else
                        {
                            input_error("unhandled adc");
                        }

                        break;
                    case "and":
                    case "or":
                    case "xor":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "and":
                                op_string = "&";
                                break;
                            case "or":
                                op_string = "|";
                                break;
                            case "xor":
                                op_string = "^";
                                break;
                            default:
                                input_error("unhandled arithmetic instruction");
                                break;
                        }

                        consolidate_parameters_size(instr_params[0], instr_params[1]);
                        string right_paren = (instr_params[0].size == 4)?"":")";

                        if ((instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp) && (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp) && (instr_params[0].paramstr == instr_params[1].paramstr))
                        {
                            if (line.word[0] == "xor")
                            {
                                add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ "0" ~ right_paren ~ ";");
                            }
                            else
                            {
                                // do nothing
                                get_parameter_read_string(instr_params[0]);
                            }
                        }
                        else
                        {
                            string right_side = get_parameter_read_string(instr_params[0]) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[1]);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ right_paren ~ ";");
                        }

                        break;
                    case "bswap":
                        if (instr_params[0].size == 4)
                        {
                            string paramstr = get_parameter_read_string(instr_params[0]);

                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ "((" ~ paramstr ~ " & 0xff000000) >> 24) | ((" ~ paramstr ~ " & 0x00ff0000) >> 8) | ((" ~ paramstr ~ " & 0x0000ff00) << 8) | ((" ~ paramstr ~ " & 0x000000ff) << 24);");
                        }
                        else
                        {
                            input_error("unhandled bswap parameters");
                        }
                        break;
                    case "call":
                        string parameters = substr_from_entry(line.line, 1, ' ');
                        string proc_name;
                        string[] arguments;
                        asm_proc *call_proc;

                        if (parameters.indexOf(' ') == -1 && parameters.indexOf(',') == -1)
                        {
                            proc_name = parameters;
                            parameters = "";
                        }
                        else
                        {
                            int index1 = cast(int)parameters.indexOf(' ');
                            int index2 = cast(int)parameters.indexOf(',');

                            if (index1 == -1 || index2 == -1 || index2 < index1)
                            {
                                input_error("unhandled procedure arguments");
                            }

                            if (parameters[index1+1..index2].strip() != "pascal")
                            {
                                input_error("unhandled procedure arguments");
                            }

                            proc_name = parameters[0..index1].strip();
                            parameters = parameters[index2+1..$].strip();

                            auto param_list = str_split_strip(parameters, ',');

                            foreach (param; param_list)
                            {
                                int arg_index = cast(int)arguments.length;
                                arguments.length++;

                                analyze_parameters(param);

                                if (instr_params[0].size == 0 && instr_params[0].type == PT.constant)
                                {
                                    instr_params[0].size = 4;
                                }

                                if (instr_params[0].size == 4)
                                {
                                    arguments[arg_index] = get_parameter_read_string(instr_params[0]);
                                }
                                else
                                {
                                    input_error("unhandled procedure arguments");
                                }
                            }
                        }

                        call_proc = find_proc(proc_name);

                        if (call_proc == null && proc_name.indexOf('[') >= 0)
                        {
                            analyze_parameters(proc_name);
                            if (instr_params[0].type == PT.memory && instr_params[0].isstructref)
                            {
                                call_proc = find_proc(instr_params[0].struct_name ~ "." ~ instr_params[0].struct_ref);
                                if (call_proc != null)
                                {
                                    proc_name = get_parameter_read_string(instr_params[0]);
                                }
                            }
                        }

                        if (call_proc != null)
                        {
                            string return_str = "";
                            string arguments_str = "";

                            foreach (i; 0..arguments.length)
                            {
                                if (call_proc.arguments.length < i + 1)
                                {
                                    input_error("wrong procedure argument");
                                }

                                if (call_proc.arguments[i].type != PPT.variable)
                                {
                                    input_error("wrong procedure argument");
                                }
                            }

                            foreach (i, argument; call_proc.arguments)
                            {
                                string argument_str;
                                if (argument.type == PPT.variable)
                                {
                                    if (arguments.length < i + 1)
                                    {
                                        input_error("wrong procedure argument");
                                    }

                                    if (argument.floatarg)
                                    {
                                        input_error("float procedure argument");
                                    }

                                    argument_str = arguments[i];
                                }
                                else
                                {
                                    if (argument.type == PPT.register)
                                    {
                                        argument_str = argument.name;

                                        current_state.regs[argument.name].used = true;
                                        if (argument.input)
                                        {
                                            if (register_has_unknown_value(argument.name))
                                            {
                                                current_state.regs[argument.name].read_unknown = true;
                                            }
                                        }

                                        if (argument.output)
                                        {
                                            current_state.regs[argument.name].value = "".idup;
                                        }
                                    }
                                    else if (argument.type == PPT.fpu_reg)
                                    {
                                        argument_str = get_fpu_reg_string(argument.fpuindex, 0);
                                        if (argument.input)
                                        {
                                            get_fpu_reg_string(argument.fpuindex, FF.read);
                                        }

                                        if (argument.output)
                                        {
                                            get_fpu_reg_string(argument.fpuindex, FF.write);
                                        }
                                    }
                                    else
                                    {
                                        input_error("wrong procedure argument");
                                    }
                                }

                                arguments_str = ((arguments_str == "")?"":arguments_str ~ ", ") ~ argument_str;
                            }

                            foreach (reg; call_proc.scratch_regs_list.keys)
                            {
                                if (current_state.regs[reg].used)
                                {
                                    current_state.regs[reg].value = reg.idup ~ "_unk_" ~ to!string(current_line);
                                }
                                else
                                {
                                    current_state.regs[reg].trashed = true;
                                }
                            }

                            if (call_proc.return_reg != "")
                            {
                                return_str = call_proc.return_reg ~ " = ";
                                current_state.regs[call_proc.return_reg].used = true;
                                current_state.regs[call_proc.return_reg].value = "".idup;
                            }

                            foreach (fpu_reg; call_proc.scratch_fpu_regs_list.keys)
                            {
                                int index = current_state.fpu_index + fpu_reg;

                                if (index >= current_state.fpu_min_index && index <= current_state.fpu_max_index)
                                {
                                    if (index <= 9)
                                    {
                                        current_state.fpu_regs[9-index].write = true;
                                    }
                                }
                            }

                            add_output_line("\t" ~ return_str ~ proc_name ~ "(" ~ arguments_str ~ ");");

                            current_state.fpu_index += call_proc.fpu_index;
                        }
                        else
                        {
                            // todo:
                            add_output_line("// todo: " ~ line.orig);
                        }

                        break;
                    case "cdq":
                        current_state.regs["eax"].used = true;
                        if (register_has_unknown_value("eax"))
                        {
                            current_state.regs["eax"].read_unknown = true;
                        }

                        current_state.regs["edx"].used = true;
                        current_state.regs["edx"].value = "".idup;

                        add_output_line("\tedx = ((int32_t)eax) >> 31;");

                        break;
                    case "cmp":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);

                        get_parameter_read_string(instr_params[0]);
                        get_parameter_read_string(instr_params[1]);

                        break;
                    case "dec":
                    case "inc":
                        string op_string;
                        uint op_flags = 0;

                        switch (line.word[0])
                        {
                            case "dec":
                                op_string = "-";
                                if (lines[current_line + 1].word[0] == "js" || lines[current_line + 1].word[0] == "jns" || lines[current_line + 1].word[0] == "jz" || lines[current_line + 1].word[0] == "jnz" ||
                                    lines[current_line + 1].word[0] == "jg" || lines[current_line + 1].word[0] == "jge" || lines[current_line + 1].word[0] == "jl" || lines[current_line + 1].word[0] == "jle")
                                {
                                    op_flags = PF.signed;
                                }
                                break;
                            case "inc":
                                op_string = "+";
                                break;
                            default:
                                input_error("unhandled arithmetic instruction");
                                break;
                        }

                        string right_side = get_parameter_read_string(instr_params[0], op_flags) ~ " " ~ op_string ~ " 1";
                        add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ((instr_params[0].size == 4)?"":")") ~ ";");

                        break;
                    case "div":
                        if (instr_params[0].size == 4)
                        {
                            current_state.regs["eax"].used = true;
                            if (register_has_unknown_value("eax"))
                            {
                                current_state.regs["eax"].read_unknown = true;
                            }
                            current_state.regs["eax"].value = "".idup;

                            current_state.regs["edx"].used = true;
                            if (register_has_unknown_value("edx"))
                            {
                                current_state.regs["edx"].read_unknown = true;
                            }
                            current_state.regs["edx"].value = "".idup;


                            string paramstr = get_parameter_read_string(instr_params[0]);
                            string div_str;
                            if (lines[current_line - 1].word[0] == "xor")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                                consolidate_parameters_size(instr_params[0], instr_params[1]);
                            }

                            if (lines[current_line - 1].word[0] == "xor" && instr_params[0].type == PT.register && instr_params[1].type == PT.register && instr_params[0].paramstr == "edx" && instr_params[1].paramstr == "edx")
                            {
                                div_str = "(uint64_t)eax";
                            }
                            else
                            {
                                div_str = "(((uint64_t)edx) << 32) | eax";
                            }

                            add_output_line("\t{ uint64_t d1 = " ~ div_str ~ "; uint32_t d2 = " ~ paramstr ~ "; eax = d1 / d2; edx = d1 % d2; }");
                        }
                        else
                        {
                            input_error("unhandled idiv parameters");
                        }
                        break;
                    case "enter":
                        if (lines[current_line + 1].word[0] == "pushad" && instr_params[0].type == PT.constant && instr_params[1].type == PT.constant && instr_params[0].paramstr == "0" && instr_params[1].paramstr == "0")
                        {
                            // no op
                        }
                        else
                        {
                            input_error("unhandled enter parameters");
                        }
                        break;
                    case "idiv":
                        if (instr_params[0].size == 4)
                        {
                            current_state.regs["eax"].used = true;
                            if (register_has_unknown_value("eax"))
                            {
                                current_state.regs["eax"].read_unknown = true;
                            }
                            current_state.regs["eax"].value = "".idup;

                            current_state.regs["edx"].used = true;
                            if (register_has_unknown_value("edx"))
                            {
                                current_state.regs["edx"].read_unknown = true;
                            }
                            current_state.regs["edx"].value = "".idup;

                            string div_str;
                            if (lines[current_line - 1].word[0] == "cdq")
                            {
                                div_str = "(int64_t)(int32_t)eax";
                            }
                            else
                            {
                                div_str = "(((uint64_t)edx) << 32) | eax";
                            }

                            add_output_line("\t{ int64_t d1 = " ~ div_str ~ "; int32_t d2 = " ~ get_parameter_read_string(instr_params[0], PF.signed) ~ "; eax = d1 / d2; edx = d1 % d2; }");
                        }
                        else
                        {
                            input_error("unhandled idiv parameters");
                        }
                        break;
                    case "imul":
                        if (instr_params.length == 1)
                        {
                            if (instr_params[0].size == 4)
                            {
                                current_state.regs["eax"].used = true;
                                if (register_has_unknown_value("eax"))
                                {
                                    current_state.regs["eax"].read_unknown = true;
                                }
                                current_state.regs["eax"].value = "".idup;

                                current_state.regs["edx"].used = true;
                                current_state.regs["edx"].value = "".idup;

                                add_output_line("\t{ uint64_t m = ((int64_t)(int32_t)eax) * " ~ get_parameter_read_string(instr_params[0], PF.signed) ~ "; eax = (uint32_t)m; edx = (uint32_t)(m >> 32); }");
                            }
                            else
                            {
                                input_error("unhandled imul parameters");
                            }
                        }
                        else if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                string right_side = get_parameter_read_string(instr_params[0], PF.signed) ~ " * " ~ get_parameter_read_string(instr_params[1], PF.signed);
                                add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                            }
                            else
                            {
                                input_error("unhandled imul parameters");
                            }
                        }
                        else if (instr_params.length == 3)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                string right_side = get_parameter_read_string(instr_params[1], PF.signed) ~ " * " ~ get_parameter_read_string(instr_params[2], PF.signed);
                                add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                            }
                            else
                            {
                                input_error("unhandled imul parameters");
                            }
                        }
                        else
                        {
                            input_error("unhandled imul parameters");
                        }

                        break;
                    case "ja":
                    case "jae":
                    case "jb":
                    case "jbe":
                    case "jna":
                    case "je":
                    case "jne":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        string compare_string;

                        switch (line.word[0])
                        {
                            case "ja":
                                compare_string = ">";
                                break;
                            case "jae":
                                compare_string = ">=";
                                break;
                            case "jb":
                                compare_string = "<";
                                break;
                            case "jbe":
                            case "jna":
                                compare_string = "<=";
                                break;
                            case "je":
                                compare_string = "==";
                                break;
                            case "jne":
                                compare_string = "!=";
                                break;
                            default:
                                input_error("unhandled jmp instruction");
                                break;
                        }

                        if (lines[current_line - 1].word[0] == "cmp" || ((lines[current_line - 1].word[0] == "ja" || lines[current_line - 1].word[0] == "je") && lines[current_line - 2].word[0] == "cmp"))
                        {
                            if (lines[current_line - 1].word[0] == "cmp")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            }
                            else
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 2].line, 1, ' '));
                            }
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0]) ~ " " ~ compare_string ~ " " ~ get_parameter_read_string(instr_params[1]) ~ ") goto " ~ labelname ~ ";");
                        }
                        else if (lines[current_line - 1].word[0] == "sahf" && (lines[current_line - 2].word[0] == "fstsw" || lines[current_line - 2].word[0] == "fnstsw") && lines[current_line - 2].word[1] == "ax" && (lines[current_line - 3].word[0] == "fcom" || lines[current_line - 3].word[0] == "fcomp" || lines[current_line - 3].word[0] == "fcompp" || lines[current_line - 3].word[0] == "ftst" || lines[current_line - 3].word[0] == "ficomp"))
                        {
                            if (lines[current_line - 3].word[0] == "fcom" || lines[current_line - 3].word[0] == "fcomp")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 3].line, 1, ' '));

                                if (lines[current_line - 3].word[0] == "fcomp")
                                {
                                    current_state.fpu_index ++;
                                }

                                if (instr_params.length == 2)
                                {
                                    consolidate_parameters_size(instr_params[0], instr_params[1]);
                                    input_error("unhandled jump - fcom parameters");
                                }
                                else
                                {
                                    add_output_line("\tif (" ~ get_fpu_reg_string(0, FF.read) ~ " " ~ compare_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.floattype) ~ ") goto " ~ labelname ~ ";");
                                }

                                if (lines[current_line - 3].word[0] == "fcomp")
                                {
                                    current_state.fpu_index --;
                                }
                            }
                            else if (lines[current_line - 3].word[0] == "ficomp")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 3].line, 1, ' '));

                                if (lines[current_line - 3].word[0] == "ficomp")
                                {
                                    current_state.fpu_index ++;
                                }

                                add_output_line("\tif (" ~ get_fpu_reg_string(0, FF.read) ~ " " ~ compare_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.signed) ~ ") goto " ~ labelname ~ ";");

                                if (lines[current_line - 3].word[0] == "ficomp")
                                {
                                    current_state.fpu_index --;
                                }
                            }
                            else if (lines[current_line - 3].word[0] == "fcompp")
                            {
                                add_output_line("\tif (" ~ get_fpu_reg_string(-2, FF.read) ~ " " ~ compare_string ~ " " ~ get_fpu_reg_string(-1, FF.read) ~ ") goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                add_output_line("\tif (" ~ get_fpu_reg_string(0, FF.read) ~ " " ~ compare_string ~ " 0.0) goto " ~ labelname ~ ";");
                            }
                        }
                        else
                        {
                            input_error("unhandled jump condition");
                        }

                        break;
                    case "jc":
                    case "jnc":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        string compare_string;

                        if (lines[current_line - 1].word[0] == "sahf" && (lines[current_line - 2].word[0] == "xor" || lines[current_line - 2].word[0] == "mov"))
                        {
                            switch (line.word[0])
                            {
                                case "jc":
                                    compare_string = "!=";
                                    break;
                                case "jnc":
                                    compare_string = "==";
                                    break;
                                default:
                                    input_error("unhandled jmp instruction");
                                    break;
                            }

                            analyze_parameters(substr_from_entry(lines[current_line - 2].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if ((lines[current_line - 2].word[0] == "xor") && (instr_params[0].size == 1) && (instr_params[0].type == PT.register) && (instr_params[0].paramstr == "ah"))
                            {
                                add_output_line("\tif ((eax & 0x100) " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else if ((lines[current_line - 2].word[0] == "mov") && (instr_params[1].size == 1) && (instr_params[1].type == PT.register) && (instr_params[1].paramstr == "ah"))
                            {
                                add_output_line("\tif ((eax & 0x100) " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - or parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "sub" || lines[current_line - 1].word[0] == "add")
                        {
                            switch (line.word[0])
                            {
                                case "jc":
                                    compare_string = "!=";
                                    break;
                                case "jnc":
                                    compare_string = "==";
                                    break;
                                default:
                                    input_error("unhandled jmp instruction");
                                    break;
                            }

                            //analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            //consolidate_parameters_size(instr_params[0], instr_params[1]);

                            add_output_line("\t  if (carry " ~ compare_string ~ " 0) goto " ~ labelname ~ "; }");
                        }
                        else
                        {
                            input_error("unhandled jump condition");
                        }

                        break;
                    case "jecxz":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        current_state.regs["ecx"].used = true;
                        if (register_has_unknown_value("ecx"))
                        {
                            current_state.regs["ecx"].read_unknown = true;
                        }

                        add_output_line("\tif (ecx == 0) goto " ~ labelname ~ ";");

                        break;
                    case "jg":
                    case "jge":
                    case "jl":
                    case "jnge":
                    case "jle":
                    case "jng":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        string compare_string;

                        switch (line.word[0])
                        {
                            case "jg":
                                compare_string = ">";
                                break;
                            case "jge":
                                compare_string = ">=";
                                break;
                            case "jl":
                            case "jnge":
                                compare_string = "<";
                                break;
                            case "jle":
                            case "jng":
                                compare_string = "<=";
                                break;
                            default:
                                input_error("unhandled jmp instruction");
                                break;
                        }

                        if (lines[current_line - 1].word[0] == "cmp" || (lines[current_line - 1].word[0] == "jg" && lines[current_line - 2].word[0] == "cmp"))
                        {
                            if (lines[current_line - 1].word[0] == "cmp")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            }
                            else
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 2].line, 1, ' '));
                            }
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " " ~ get_parameter_read_string(instr_params[1], PF.signed) ~ ") goto " ~ labelname ~ ";");
                        }
                        else if (lines[current_line - 1].word[0] == "or" || lines[current_line - 1].word[0] == "test")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if ((instr_params[0].size == 4) && (instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp) && (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp) && (instr_params[0].paramstr == instr_params[1].paramstr))
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - or parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "sub")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - sub parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "dec")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - sub parameters");
                            }
                        }
                        else
                        {
                            input_error("unhandled jump condition");
                        }

                        break;
                    case "jno":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        string compare_string;

                        switch (line.word[0])
                        {
                            case "jno":
                                compare_string = "!=";
                                break;
                            default:
                                input_error("unhandled jmp instruction");
                                break;
                        }

                        if (lines[current_line - 1].word[0] == "dec")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));

                            if (instr_params[0].size == 1)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0]) ~ " " ~ compare_string ~ " 0x7f) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - dec parameters");
                            }
                        }

                        break;
                    case "jns":
                    case "jnz":
                    case "js":
                    case "jz":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        string labelname = procedure_name ~ "_" ~ instr_params[0].paramstr[2..$];
                        string compare_string;

                        switch (line.word[0])
                        {
                            case "jns":
                                compare_string = ">=";
                                break;
                            case "jnz":
                                compare_string = "!=";
                                break;
                            case "js":
                                compare_string = "<";
                                break;
                            case "jz":
                                compare_string = "==";
                                break;
                            default:
                                input_error("unhandled jmp instruction");
                                break;
                        }


                        if (lines[current_line - 1].word[0] == "or" || lines[current_line - 1].word[0] == "and")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - or parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "dec" || (lines[current_line - 1].word[0] == "js" && lines[current_line - 2].word[0] == "dec"))
                        {
                            if (lines[current_line - 1].word[0] == "dec")
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            }
                            else
                            {
                                analyze_parameters(substr_from_entry(lines[current_line - 2].line, 1, ' '));
                            }

                            if (instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp || instr_params[0].type == PT.local_variable || instr_params[0].type == PT.local_struc_variable || instr_params[0].type == PT.stack_variable || instr_params[0].type == PT.variable)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - dec parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "sub")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - sub parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "sar")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - sub parameters");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "test")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            add_output_line("\tif ((" ~ get_parameter_read_string(instr_params[0]) ~ " & " ~ get_parameter_read_string(instr_params[1]) ~ ") " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                        }
                        else if (lines[current_line - 1].word[0] == "xor")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                input_error("unhandled jump - sub parameters");
                            }
                            else
                            {
                                add_output_line("\tif (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                        }
                        else if (lines[current_line - 1].word[0] == "cmp")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if ((instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp || instr_params[0].type == PT.memory) && (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp || instr_params[1].type == PT.constant))
                            {
                                add_output_line("\tif ( (" ~ get_parameter_read_string(instr_params[0], PF.signed) ~ " - " ~ get_parameter_read_string(instr_params[1], PF.signed) ~ ") " ~ compare_string ~ " 0) goto " ~ labelname ~ ";");
                            }
                            else
                            {
                                input_error("unhandled jump - cmp parameters");
                            }
                        }
                        else
                        {
                            input_error("unhandled jump condition");
                        }

                        break;
                    case "jmp":
                        define_local_label(instr_params[0].paramstr[2..$], 0, false);
                        add_output_line("\tgoto " ~ procedure_name ~ "_" ~ instr_params[0].paramstr[2..$] ~ ";");

                        if (lines[current_line + 1].line.length > 2 && lines[current_line + 1].line[0..2] == "@@")
                        {
                            int colonpos = cast(int)(lines[current_line + 1].line.indexOf(':'));
                            if (colonpos == -1)
                            {
                                input_error("label after jmp not found");
                            }
                            auto next_label = find_local_label(lines[current_line + 1].line[2..colonpos]);

                            if (next_label != null)
                            {
                                current_state.fpu_index = next_label.state.fpu_index;
                                current_state.stack_index = next_label.state.stack_index;
                                // todo: change current state ?
                            }
                            else
                            {
                                input_error("label after jmp not found");
                            }
                        }
                        else
                        {
                            input_error("missing label after jmp");
                        }

                        break;
                    case "lea":
                        if (instr_params[0].size == 4)
                        {
                            string right_side = get_parameter_read_string(instr_params[1], PF.addressof);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                        }
                        else
                        {
                            input_error("unhandled lea parameters");
                        }

                        break;
                    case "leave":
                        if (lines[current_line - 1].word[0] == "popad" && (lines[current_line + 1].word[0] == "ret" || (lines[current_line + 1].word[0] == "mov" && lines[current_line + 2].word[0] == "ret")))
                        {
                            // no op
                        }
                        else
                        {
                            input_error("unhandled leave parameters");
                        }
                        break;
                    case "mov":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);
                        if (instr_params[0].size == 4)
                        {
                            string right_side = get_parameter_read_string(instr_params[1]);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");

                            if ((instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp) && (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp))
                            {
                                current_state.regs[instr_params[0].paramstr].value = current_state.regs[instr_params[1].paramstr].value.idup;
                            }
                        }
                        else
                        {
                            string right_side = get_parameter_read_string(instr_params[1]);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ");");
                        }

                        break;
                    case "movsx":
                    case "movzx":
                        if (instr_params[0].size == 4)
                        {
                            string right_side;
                            if (line.word[0] == "movsx")
                            {
                                right_side = "(int32_t)" ~ get_parameter_read_string(instr_params[1], PF.signed);
                            }
                            else
                            {
                                right_side = "(uint32_t)" ~ get_parameter_read_string(instr_params[1]);
                            }
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                        }
                        else
                        {
                            input_error("unhandled movsx parameters");
                        }

                        break;
                    case "neg":
                        string right_side = "- " ~ get_parameter_read_string(instr_params[0], PF.signed);
                        add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ((instr_params[0].size == 4)?"":")") ~ ";");
                        break;
                    case "pop":
                        foreach (param; instr_params)
                        {
                            if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 4))
                            {
                                add_output_line("\t" ~ get_parameter_write_string(param) ~ "stack_var" ~ ((current_state.stack_index < 10)?"0":"") ~ to!string(current_state.stack_index) ~ ";");

                                current_state.regs[param.paramstr].value = current_state.stack_value[current_state.stack_index].idup;

                                current_state.stack_index --;
                            }
                            else
                            {
                                input_error("unhandled pop parameters");
                            }
                        }

                        break;
                    case "popad":
                        if (lines[current_line + 1].word[0] == "leave" && (lines[current_line + 2].word[0] == "ret" || (lines[current_line + 2].word[0] == "mov" && lines[current_line + 3].word[0] == "ret")))
                        {
                            foreach (reg; regs_list)
                            {
                                current_state.regs[reg].value = reg;
                            }
                            // no op
                        }
                        else
                        {
                            input_error("unhandled leave parameters");
                        }
                        break;
                    case "push":
                        foreach (param; instr_params)
                        {
                            if ((param.type == PT.register || param.type == PT.reg_ebp) && (param.size == 4))
                            {
                                current_state.stack_index ++;
                                if (current_state.stack_index > current_state.stack_max_index)
                                {
                                    current_state.stack_max_index = current_state.stack_index;
                                    current_state.stack_value.length++;
                                }

                                current_state.stack_value[current_state.stack_index] = current_state.regs[param.paramstr].value.idup;

                                bool change_unknown_read = (current_state.regs[param.paramstr].value == param.paramstr && !current_state.regs[param.paramstr].read_unknown);

                                add_output_line("\tstack_var" ~ ((current_state.stack_index < 10)?"0":"") ~ to!string(current_state.stack_index) ~ " = " ~ get_parameter_read_string(param) ~ ";");

                                if (change_unknown_read)
                                {
                                    current_state.regs[param.paramstr].read_unknown = false;
                                }
                            }
                            else if ((param.type == PT.local_variable) && (param.size == 4))
                            {
                                auto var = find_local_variable(param.paramstr);

                                if (!var.floattype && !var.structype && var.numitems == 1)
                                {
                                    var.inttype = true;

                                    current_state.stack_index ++;
                                    if (current_state.stack_index > current_state.stack_max_index)
                                    {
                                        current_state.stack_max_index = current_state.stack_index;
                                        current_state.stack_value.length++;
                                    }

                                    current_state.stack_value[current_state.stack_index] = "".idup;

                                    add_output_line("\tstack_var" ~ ((current_state.stack_index < 10)?"0":"") ~ to!string(current_state.stack_index) ~ " = " ~ param.paramstr ~ ";");
                                }
                                else
                                {
                                    input_error("unhandled push parameters");
                                }
                            }
                            else
                            {
                                input_error("unhandled push parameters");
                            }
                        }

                        break;
                    case "pushad":
                        if (lines[current_line - 1].word[0] == "enter")
                        {
                            // no op
                        }
                        else
                        {
                            input_error("unhandled pushad parameters");
                        }
                        break;
                    case "ret":
                        if (lines[current_line + 1].word[0] == "endp" || (lines[current_line + 1].word[1] == "endp" && procedure_name == lines[current_line + 1].line[0..lines[current_line + 1].line.indexOf(' ')]))
                        {
                            // ok
                        }
                        else
                        {
                            input_error("missing endp");
                        }

                        if (instr_params.length != 0)
                        {
                            input_error("unhandled ret parameters");
                        }

                        stdout.writeln("Procedure: " ~ procedure_name);

                        if (current_procedure != null)
                        {
                            bool proc_ok = true;

                            string unknown_read_regs = "";
                            string used_changed_regs = "";
                            string used_unchanged_regs = "";
                            string trashed_regs = "";
                            string unused_regs = "";
                            foreach (reg; current_state.regs)
                            {
                                if (reg.read_unknown)
                                {
                                    unknown_read_regs = ((unknown_read_regs == "")?"":(unknown_read_regs ~ ", ")) ~ reg.name;
                                }

                                if (reg.used)
                                {
                                    if (reg.value == reg.name)
                                    {
                                        if (reg.name in current_procedure.scratch_regs_list)
                                        {
                                            used_unchanged_regs = ((used_unchanged_regs == "")?"":(used_unchanged_regs ~ ", ")) ~ reg.name;
                                        }
                                    }
                                    else
                                    {
                                        if (! (reg.name in current_procedure.scratch_regs_list) && ! (reg.name in current_procedure.output_regs_list))
                                        {
                                            used_changed_regs = ((used_changed_regs == "")?"":(used_changed_regs ~ ", ")) ~ reg.name;
                                        }
                                    }
                                }
                                else
                                {
                                    if (reg.trashed)
                                    {
                                        if (! (reg.name in current_procedure.scratch_regs_list))
                                        {
                                            trashed_regs = ((trashed_regs == "")?"":(trashed_regs ~ ", ")) ~ reg.name;
                                        }
                                    }
                                    else
                                    {
                                        if (reg.name in current_procedure.scratch_regs_list)
                                        {
                                            unused_regs = ((unused_regs == "")?"":(unused_regs ~ ", ")) ~ reg.name;
                                        }
                                    }
                                }
                            }

                            if (unknown_read_regs != "")
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Reading regs with unknown value: " ~ unknown_read_regs);
                            }
                            if (used_changed_regs != "")
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Used regs with changed value: " ~ used_changed_regs);
                            }
                            if (used_unchanged_regs != "")
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Used regs with unchanged value: " ~ used_unchanged_regs);
                            }
                            if (trashed_regs != "")
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Unused regs with trashed value: " ~ trashed_regs);
                            }
                            if (unused_regs != "")
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Unused regs with original value: " ~ unused_regs);
                            }


                            // todo: checks, regs, fpu regs, stack vars, local vars, ...

                            if (current_state.stack_index >= 0)
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Number of remaining stack variables: " ~ to!string(current_state.stack_index + 1));
                            }

                            if (current_state.fpu_index != current_procedure.fpu_index + 9)
                            {
                                proc_ok = false;
                                stdout.writeln("Warning: Different FPU stack pointer: " ~ to!string(current_state.fpu_index - 9));
                            }
                            if (current_state.fpu_min_index <= current_state.fpu_max_index)
                            {
                                if (current_state.fpu_min_index <= 9)
                                {
                                    string input_fpu_regs = "";
                                    string ouput_fpu_regs = "";
                                    string unknown_read_fpu_regs = "";
                                    foreach (i, fpu_reg; current_state.fpu_regs)
                                    {
                                        byte fpuindex = cast(byte)(-cast(int)i);
                                        if (fpu_reg.read && !(fpuindex in current_procedure.input_fpu_regs_list) && !(fpuindex in current_procedure.scratch_fpu_regs_list))
                                        {
                                            input_fpu_regs = ((input_fpu_regs == "")?"":(input_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                        if (fpu_reg.write && !(fpuindex in current_procedure.output_fpu_regs_list) && !(fpuindex in current_procedure.scratch_fpu_regs_list))
                                        {
                                            ouput_fpu_regs = ((ouput_fpu_regs == "")?"":(ouput_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                        if (fpu_reg.read_unknown)
                                        {
                                            unknown_read_fpu_regs = ((unknown_read_fpu_regs == "")?"":(unknown_read_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                    }

                                    if (input_fpu_regs != "")
                                    {
                                        proc_ok = false;
                                        stdout.writeln("Warning: Missing input FPU regs below original FPU stack pointer: " ~ input_fpu_regs);
                                    }
                                    if (ouput_fpu_regs != "")
                                    {
                                        proc_ok = false;
                                        stdout.writeln("Warning: Missing output FPU regs below original FPU stack pointer: " ~ ouput_fpu_regs);
                                    }
                                    if (unknown_read_fpu_regs != "")
                                    {
                                        proc_ok = false;
                                        stdout.writeln("Warning: Reading FPU regs below original FPU stack pointer with unknown value: " ~ unknown_read_fpu_regs);
                                    }
                                }
                            }


                            if (proc_ok)
                            {
                                stdout.writeln("OK");
                            }
                        }
                        else
                        {
                            string unknown_read_regs = "";
                            string used_changed_regs = "";
                            string used_unchanged_regs = "";
                            string trashed_regs = "";
                            string unused_regs = "";
                            foreach (reg; current_state.regs)
                            {
                                if (reg.read_unknown)
                                {
                                    unknown_read_regs = ((unknown_read_regs == "")?"":(unknown_read_regs ~ ", ")) ~ reg.name;
                                }

                                if (reg.used)
                                {
                                    if (reg.value == reg.name)
                                    {
                                        used_unchanged_regs = ((used_unchanged_regs == "")?"":(used_unchanged_regs ~ ", ")) ~ reg.name;
                                    }
                                    else
                                    {
                                        used_changed_regs = ((used_changed_regs == "")?"":(used_changed_regs ~ ", ")) ~ reg.name;
                                    }
                                }
                                else
                                {
                                    if (reg.trashed)
                                    {
                                        trashed_regs = ((trashed_regs == "")?"":(trashed_regs ~ ", ")) ~ reg.name;
                                    }
                                    else
                                    {
                                        unused_regs = ((unused_regs == "")?"":(unused_regs ~ ", ")) ~ reg.name;
                                    }
                                }
                            }

                            if (unknown_read_regs != "")
                            {
                                stdout.writeln("Warning: Reading regs with unknown value: " ~ unknown_read_regs);
                            }
                            if (used_changed_regs != "")
                            {
                                stdout.writeln("Used regs with changed value: " ~ used_changed_regs);
                            }
                            if (used_unchanged_regs != "")
                            {
                                stdout.writeln("Used regs with unchanged value: " ~ used_unchanged_regs);
                            }
                            if (trashed_regs != "")
                            {
                                stdout.writeln("Unused regs with trashed value: " ~ trashed_regs);
                            }
                            if (unused_regs != "")
                            {
                                stdout.writeln("Unused regs with original value: " ~ unused_regs);
                            }

                            if (current_state.stack_max_index >= 0)
                            {
                                stdout.writeln("Number of stack variables: " ~ to!string(current_state.stack_max_index + 1));
                            }
                            if (current_state.stack_index >= 0)
                            {
                                stdout.writeln("Warning: Number of remaining stack variables: " ~ to!string(current_state.stack_index + 1));
                            }


                            if (current_state.fpu_min_index <= current_state.fpu_max_index)
                            {
                                stdout.writeln("Used FPU regs: " ~ to!string(current_state.fpu_min_index) ~ " - " ~ to!string(current_state.fpu_max_index));

                                if (current_state.fpu_index != 9)
                                {
                                    stdout.writeln("Warning: Changed FPU stack pointer: " ~ to!string(current_state.fpu_index - 9));
                                }
                                if (current_state.fpu_min_index <= 9)
                                {
                                    stdout.writeln("Warning: Using FPU regs below original FPU stack pointer: " ~ to!string(10 - current_state.fpu_min_index));

                                    string input_fpu_regs = "";
                                    string ouput_fpu_regs = "";
                                    string unknown_read_fpu_regs = "";
                                    foreach (i, fpu_reg; current_state.fpu_regs)
                                    {
                                        if (fpu_reg.read)
                                        {
                                            input_fpu_regs = ((input_fpu_regs == "")?"":(input_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                        if (fpu_reg.write)
                                        {
                                            ouput_fpu_regs = ((ouput_fpu_regs == "")?"":(ouput_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                        if (fpu_reg.read_unknown)
                                        {
                                            unknown_read_fpu_regs = ((unknown_read_fpu_regs == "")?"":(unknown_read_fpu_regs ~ ", ")) ~ to!string(9 - i);
                                        }
                                    }

                                    if (input_fpu_regs != "")
                                    {
                                        stdout.writeln("Input FPU regs below original FPU stack pointer: " ~ input_fpu_regs);
                                    }
                                    if (ouput_fpu_regs != "")
                                    {
                                        stdout.writeln("Output FPU regs below original FPU stack pointer: " ~ ouput_fpu_regs);
                                    }
                                    if (unknown_read_fpu_regs != "")
                                    {
                                        stdout.writeln("Warning: Reading FPU regs below original FPU stack pointer with unknown value: " ~ unknown_read_fpu_regs);
                                    }
                                }
                            }
                        }

                        // define fpu registers
                        string fpu_register_list = "";
                        if (current_state.fpu_min_index <= current_state.fpu_max_index)
                        {
                            foreach (i; current_state.fpu_min_index..current_state.fpu_max_index+1)
                            {
                                string reg_def = get_fpu_reg_string(current_state.fpu_index - i, 0);

                                if (i < 10)
                                {
                                    byte index = cast(byte)(9 - i);
                                    if (!current_state.fpu_regs[index].read && !current_state.fpu_regs[index].write)
                                    {
                                        continue;
                                    }

                                    if (current_procedure != null && -index in current_procedure.input_fpu_regs_list)
                                    {
                                        reg_def ~= " = _" ~ reg_def;
                                    }
                                }

                                fpu_register_list = ((fpu_register_list == "")?"":(fpu_register_list ~ ", ")) ~ reg_def;
                            }
                        }
                        if (fpu_register_list != "")
                        {
                            int saved_current_line = current_line;
                            current_line = procedure_linenum;

                            add_output_line("\t" ~ fpureg_datatype_name ~ " " ~ fpu_register_list ~ ";");

                            current_line = saved_current_line;
                        }

                        // define registers
                        string register_list = "";
                        foreach (reg; current_state.regs)
                        {
                            if (reg.used)
                            {
                                string reg_def = reg.name;

                                if (current_procedure != null && reg.name in current_procedure.input_regs_list)
                                {
                                    reg_def ~= " = _" ~ reg.name;
                                }

                                register_list = ((register_list == "")?"":(register_list ~ ", ")) ~ reg_def;
                            }
                        }
                        if (register_list != "")
                        {
                            int saved_current_line = current_line;
                            current_line = procedure_linenum;

                            add_output_line("\tuint32_t " ~ register_list ~ ";");

                            current_line = saved_current_line;
                        }

                        // define local stack variables
                        string stack_variable_list = "";
                        if (current_state.stack_max_index >= 0)
                        {
                            foreach (i; 0..current_state.stack_max_index+1)
                            {
                                stack_variable_list = ((stack_variable_list == "")?"":(stack_variable_list ~ ", ")) ~ "stack_var" ~ ((i < 10)?"0":"") ~ to!string(i);
                            }
                        }
                        if (stack_variable_list != "")
                        {
                            int saved_current_line = current_line;
                            current_line = procedure_linenum;

                            add_output_line("\tuint32_t " ~ stack_variable_list ~ ";");

                            current_line = saved_current_line;
                        }

                        // define local variables
                        string last_basetype = "";
                        int last_linenum = 0;
                        string variable_list = "";
                        foreach (var; local_variables)
                        {
                            if (var.argument)
                            {
                                if (var.structype)
                                {
                                    input_error("wrong argument type: " ~ var.name);
                                }
                                else if (current_procedure != null)
                                {
                                    foreach (arg; current_procedure.arguments)
                                    {
                                        if (arg.name == var.name)
                                        {
                                            if (arg.floatarg)
                                            {
                                                if (!var.floattype)
                                                {
                                                    input_error("wrong argument type: " ~ var.name);
                                                }
                                            }
                                            else
                                            {
                                                if (var.floattype)
                                                {
                                                    input_error("wrong argument type: " ~ var.name);
                                                }
                                            }
                                        }
                                    }
                                }
                                else
                                {
                                    if (var.floattype)
                                    {
                                        stdout.writeln("Warning: Floating point argument: " ~ var.name);
                                    }
                                }

                                // todo: argument check ?
                                // already done in "arg" ?
                                continue;
                            }

                            string basetype;

                            if (var.inttype)
                            {
                                if (var.size == 4 || var.size == 2 || var.size == 1)
                                {
                                    basetype = "uint" ~ to!string(var.size * 8) ~ "_t";
                                }
                                else
                                {
                                    input_error("unhandled local variable type: " ~ var.name);
                                }
                            }
                            else if (var.floattype)
                            {
                                if (var.size == 4)
                                {
                                    basetype = "float";
                                }
                                else
                                {
                                    input_error("unhandled local variable type: " ~ var.name);
                                }
                            }
                            else if (var.structype)
                            {
                                basetype = var.type_name;
                            }
                            else
                            {
                                if (var.size == 4 || var.size == 2 || var.size == 1)
                                {
                                    basetype = "int" ~ to!string(var.size * 8) ~ "_t";
                                }
                                else
                                {
                                    input_error("unknown local variable type: " ~ var.name);
                                }
                            }

                            string varextent;
                            if (var.numitems == 1)
                            {
                                varextent = "";
                            }
                            else if (var.numitems > 1)
                            {
                                varextent = "[" ~ to!string(var.numitems) ~ "]";
                            }
                            else
                            {
                                input_error("unhandled local variable extent: " ~ var.name);
                            }

                            if (last_basetype != basetype || last_linenum != var.linenum)
                            {
                                if (last_linenum != 0)
                                {
                                    int saved_current_line = current_line;
                                    current_line = last_linenum;

                                    add_output_line("\t" ~ last_basetype ~ " " ~ variable_list ~ ";");

                                    current_line = saved_current_line;
                                }

                                last_basetype = basetype;
                                last_linenum = var.linenum;
                                variable_list = var.name ~ varextent;
                            }
                            else
                            {
                                variable_list ~= ", " ~ var.name ~ varextent;
                            }
                        }
                        if (last_linenum != 0)
                        {
                            int saved_current_line = current_line;
                            current_line = last_linenum;

                            add_output_line("\t" ~ last_basetype ~ " " ~ variable_list ~ ";");

                            current_line = saved_current_line;
                        }


                        bool do_return = true;
                        // output parameters
                        if (current_procedure != null)
                        {
                            foreach (reg; current_procedure.output_regs_list.keys)
                            {
                                add_output_line("\t_" ~ reg ~ " = " ~ reg ~ ";");
                                do_return = false;
                            }

                            foreach (i; current_procedure.output_fpu_regs_list.keys.sort)
                            {
                                string fpu_reg = get_fpu_reg_string((current_state.fpu_index - 9) - i, 0);
                                add_output_line("\t_" ~ fpu_reg ~ " = " ~ fpu_reg ~ ";");
                                do_return = false;
                            }

                            foreach (i; 0..current_procedure.fpu_index)
                            {
                                string fpu_reg = get_fpu_reg_string((current_state.fpu_index - 10) - i, 0);
                                add_output_line("\t_" ~ fpu_reg ~ " = " ~ fpu_reg ~ ";");
                                do_return = false;
                            }

                            if (current_procedure.return_reg != "")
                            {
                                add_output_line("\treturn " ~ current_procedure.return_reg ~ ";");
                                do_return = false;
                            }
                        }

                        if (do_return)
                        {
                            add_output_line("\treturn;");
                        }

                        add_output_line("}");

                        stdout.writeln("");

                        in_proc = false;
                        current_procedure = null;
                        current_line++;
                        break;
                    case "rol":
                        if (instr_params[0].size == 4)
                        {
                            string param1str = get_parameter_read_string(instr_params[1]);
                            string param0str = get_parameter_read_string(instr_params[0]);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ "(" ~ param0str ~ " << " ~ param1str ~ ") | (" ~ param0str ~ " >> (32 - " ~ param1str ~ "));");
                        }
                        else
                        {
                            input_error("unhandled rol parameters");
                        }

                        break;
                    case "sahf":

                        if (lines[current_line - 1].word[0] == "fstsw" || lines[current_line - 1].word[0] == "fnstsw")
                        {
                            // ok
                        }
                        else if (lines[current_line - 1].word[0] == "xor" && lines[current_line + 1].word[0] == "jnc")
                        {
                            // ok
                        }
                        else if (lines[current_line - 1].word[0] == "mov" && lines[current_line + 1].word[0] == "jc")
                        {
                            // ok
                        }
                        else
                        {
                            input_error("unhandled sahf instruction");
                        }

                        break;
                    case "sal":
                    case "sar":
                    case "shl":
                    case "shr":
                        string op_string;
                        uint op_flags = 0;

                        switch (line.word[0])
                        {
                            case "sal":
                            case "shl":
                                op_string = "<<";
                                break;
                            case "sar":
                                op_flags = PF.signed;
                                op_string = ">>";
                                break;
                            case "shr":
                                op_string = ">>";
                                break;
                            default:
                                input_error("unhandled arithmetic instruction");
                                break;
                        }

                        if (instr_params[0].size == 4)
                        {
                            string right_side = get_parameter_read_string(instr_params[0], op_flags) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[1]);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                        }
                        else
                        {
                            input_error("unhandled shl parameters");
                        }

                        break;
                    case "setae":
                        string compare_string;

                        switch (line.word[0])
                        {
                            case "setae":
                                compare_string = ">=";
                                break;
                            default:
                                input_error("unhandled set instruction");
                                break;
                        }

                        string left_side;
                        if (instr_params[0].size == 1)
                        {
                            left_side = get_parameter_write_string(instr_params[0]);
                        }
                        else
                        {
                            input_error("unhandled set parameters");
                        }

                        if (lines[current_line - 1].word[0] == "cmp")
                        {
                            analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));
                            consolidate_parameters_size(instr_params[0], instr_params[1]);

                            if (instr_params[0].size == 4)
                            {
                                add_output_line("\t" ~ left_side ~ "(" ~ get_parameter_read_string(instr_params[0]) ~ " " ~ compare_string ~ " " ~ get_parameter_read_string(instr_params[1]) ~ ")?1:0);");
                            }
                            else
                            {
                                input_error("unhandled set - cmp parameters");
                            }
                        }
                        else
                        {
                            input_error("unhandled set condition");
                        }

                        break;
                    case "shld":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);

                        if (instr_params[0].size == 4)
                        {
                            string param2str = get_parameter_read_string(instr_params[2]);
                            string right_side = "(" ~ get_parameter_read_string(instr_params[0]) ~ " << " ~ param2str ~ ") | (" ~ get_parameter_read_string(instr_params[1]) ~ " >> (32 - " ~ param2str ~ "))";
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                        }
                        else
                        {
                            input_error("unhandled shld parameters");
                        }

                        break;
                    case "shrd":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);

                        if (instr_params[0].size == 4)
                        {
                            string param2str = get_parameter_read_string(instr_params[2]);
                            string right_side = "(" ~ get_parameter_read_string(instr_params[0]) ~ " >> " ~ param2str ~ ") | (" ~ get_parameter_read_string(instr_params[1]) ~ " << (32 - " ~ param2str ~ "))";
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ right_side ~ ";");
                        }
                        else
                        {
                            input_error("unhandled shrd parameters");
                        }

                        break;
                    case "test":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);

                        get_parameter_read_string(instr_params[0]);
                        get_parameter_read_string(instr_params[1]);

                        break;
                    case "xchg":
                        consolidate_parameters_size(instr_params[0], instr_params[1]);
                        if (instr_params[0].size == 4)
                        {
                            string oldval0 = (instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp)?current_state.regs[instr_params[0].paramstr].value:"";
                            string oldval1 = (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp)?current_state.regs[instr_params[1].paramstr].value:"";
                            string param0str = get_parameter_read_string(instr_params[0]);
                            string param1str = get_parameter_read_string(instr_params[1]);
                            add_output_line("\t{ uint32_t value = " ~ param0str ~ "; " ~ get_parameter_write_string(instr_params[0]) ~ param1str ~ "; " ~ get_parameter_write_string(instr_params[1]) ~ "value; }");

                            if ((instr_params[0].type == PT.register || instr_params[0].type == PT.reg_ebp) && (instr_params[1].type == PT.register || instr_params[1].type == PT.reg_ebp))
                            {
                                current_state.regs[instr_params[0].paramstr].value = oldval1.idup;
                                current_state.regs[instr_params[1].paramstr].value = oldval0.idup;
                            }
                        }
                        else
                        {
                            input_error("unhandled xchg parameters");
                        }

                        break;
                    default:
                        input_error("unhandled x86 instruction");
                        break;
                }


                current_line++;
                continue;
            }

            if (is_x87_instruction(line.word[0]))
            {
                analyze_parameters(substr_from_entry(line.line, 1, ' '));

                switch (line.word[0])
                {
                    case "fabs":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = fabs" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        break;
                    case "fadd":
                    case "fdiv":
                    case "fmul":
                    case "fsub":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "fadd":
                                op_string = "+";
                                break;
                            case "fdiv":
                                op_string = "/";
                                break;
                            case "fmul":
                                op_string = "*";
                                break;
                            case "fsub":
                                op_string = "-";
                                break;
                            default:
                                input_error("unhandled floating arithmetic instruction");
                                break;
                        }

                        if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                            string right_side = get_parameter_read_string(instr_params[0], PF.floattype) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[1], PF.floattype);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }
                        else
                        {
                            string param1str = get_parameter_read_string(instr_params[0], PF.floattype);
                            string param0str = get_fpu_reg_string(0, FF.rw);

                            add_output_line("\t" ~ param0str ~ " = " ~ param0str ~ " " ~ op_string ~ " " ~ param1str ~ ";");
                        }

                        break;
                    case "faddp":
                    case "fdivp":
                    case "fmulp":
                    case "fsubp":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "faddp":
                                op_string = "+";
                                break;
                            case "fdivp":
                                op_string = "/";
                                break;
                            case "fmulp":
                                op_string = "*";
                                break;
                            case "fsubp":
                                op_string = "-";
                                break;
                            default:
                                input_error("unhandled floating arithmetic instruction");
                                break;
                        }

                        if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                            string right_side = get_parameter_read_string(instr_params[0], PF.floattype) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[1], PF.floattype);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }
                        else
                        {
                            string right_side = get_parameter_read_string(instr_params[0], PF.floattype) ~ " " ~ op_string ~ " " ~ get_fpu_reg_string(0, FF.read);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }

                        current_state.fpu_index --;
                        break;
                    case "fchs":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = -" ~ param0str ~ ";");
                        break;
                    case "fcom":
                    case "fcomp":
                        if (instr_params.length == 0)
                        {
                            input_error("unhandled fcom parameters");
                        }
                        else if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                            get_parameter_read_string(instr_params[0], PF.floattype);
                            get_parameter_read_string(instr_params[1], PF.floattype);
                        }
                        else
                        {
                            get_parameter_read_string(instr_params[0], PF.floattype);
                        }

                        if (line.word[0] == "fcomp")
                        {
                            current_state.fpu_index --;
                        }
                        break;
                    case "fcompp":
                        get_fpu_reg_string(0, FF.read);
                        get_fpu_reg_string(1, FF.read);

                        current_state.fpu_index -= 2;
                        break;
                    case "fcos":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = cos" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        break;
                    case "fdivr":
                    case "fsubr":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "fdivr":
                                op_string = "/";
                                break;
                            case "fsubr":
                                op_string = "-";
                                break;
                            default:
                                input_error("unhandled floating arithmetic instruction");
                                break;
                        }

                        if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                            string right_side = get_parameter_read_string(instr_params[1], PF.floattype) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.floattype);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }
                        else
                        {
                            string param1str = get_parameter_read_string(instr_params[0], PF.floattype);
                            string param0str = get_fpu_reg_string(0, FF.rw);
                            add_output_line("\t" ~ param0str ~ " = " ~ param1str ~ " " ~ op_string ~ " " ~ param0str ~ ";");
                        }

                        break;
                    case "fdivrp":
                    case "fsubrp":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "fdivrp":
                                op_string = "/";
                                break;
                            case "fsubrp":
                                op_string = "-";
                                break;
                            default:
                                input_error("unhandled floating arithmetic instruction");
                                break;
                        }

                        if (instr_params.length == 2)
                        {
                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                            string right_side = get_parameter_read_string(instr_params[1], PF.floattype) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.floattype);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }
                        else
                        {
                            string right_side = get_fpu_reg_string(0, FF.read) ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.floattype);
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ right_side ~ ";");
                        }

                        current_state.fpu_index --;
                        break;
                    case "ficomp":
                        get_parameter_read_string(instr_params[0], PF.signed);

                        if (line.word[0] == "ficomp")
                        {
                            current_state.fpu_index --;
                        }
                        break;
                    case "ffree":
                        add_output_line("\t// " ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ "0.0" ~ fpureg_datatype_suffix ~ ";");

                        break;
                    case "fiadd":
                    case "fidiv":
                    case "fimul":
                    case "fisub":
                        string op_string;

                        switch (line.word[0])
                        {
                            case "fiadd":
                                op_string = "+";
                                break;
                            case "fidiv":
                                op_string = "/";
                                break;
                            case "fimul":
                                op_string = "*";
                                break;
                            case "fisub":
                                op_string = "-";
                                break;
                            default:
                                input_error("unhandled floating arithmetic instruction");
                                break;
                        }

                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = " ~ param0str ~ " " ~ op_string ~ " " ~ get_parameter_read_string(instr_params[0], PF.signed) ~ ";");

                        break;
                    case "fild":
                        current_state.fpu_index ++;

                        if (instr_params[0].size == 4)
                        {
                            add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = " ~ get_parameter_read_string(instr_params[0], PF.signed) ~ ";");
                        }
                        else
                        {
                            input_error("unhandled fild parameters");
                        }

                        break;
                    case "fist":
                    case "fistp":
                        if (instr_params[0].size == 4)
                        {
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0]) ~ "(int32_t)" ~ get_rounding_function() ~ "(" ~ get_fpu_reg_string(0, FF.read) ~ ");");
                        }
                        else
                        {
                            input_error("unhandled fist parameters");
                        }

                        if (line.word[0] == "fistp")
                        {
                            current_state.fpu_index --;
                        }
                        break;
                    case "fld":
                        string param1str = get_parameter_read_string(instr_params[0], PF.floattype);

                        current_state.fpu_index ++;

                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = " ~ param1str ~ ";");

                        break;
                    case "fld1":
                        current_state.fpu_index ++;
                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = 1.0" ~ fpureg_datatype_suffix ~ ";");
                        break;
                    case "fldpi":
                        current_state.fpu_index ++;
                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = " ~ ((fpureg_datatype == FPU_DT.FLOAT)?"(float)":"") ~ "M_PI;");
                        break;
                    case "fldz":
                        current_state.fpu_index ++;
                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = 0.0" ~ fpureg_datatype_suffix ~ ";");
                        break;
                    case "fpatan":
                        string param0str = get_fpu_reg_string(0, FF.read);
                        string param1str = get_fpu_reg_string(1, FF.rw);
                        add_output_line("\t" ~ param1str ~ " = atan2" ~ fpureg_datatype_suffix ~ "(" ~ param1str ~ ", " ~ param0str ~ ");");
                        current_state.fpu_index --;
                        break;
                    case "fptan":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = tan" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        current_state.fpu_index ++;
                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = 1.0" ~ fpureg_datatype_suffix ~ ";");
                        break;
                    case "frndint":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = " ~ get_rounding_function() ~ "(" ~ param0str ~ ");");

                        break;
                    case "fscale":
                        string param1str = get_fpu_reg_string(1, FF.read);
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = " ~ param0str ~ " * exp2" ~ fpureg_datatype_suffix ~ "(trunc" ~ fpureg_datatype_suffix ~ "(" ~ param1str ~ "));");
                        break;
                    case "fsin":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = sin" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        break;
                    case "fsincos":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        current_state.fpu_index ++;
                        add_output_line("\t" ~ get_fpu_reg_string(0, FF.write) ~ " = cos" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        add_output_line("\t" ~ param0str ~ " = sin" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        break;
                    case "fsqrt":
                        string param0str = get_fpu_reg_string(0, FF.rw);
                        add_output_line("\t" ~ param0str ~ " = sqrt" ~ fpureg_datatype_suffix ~ "(" ~ param0str ~ ");");
                        break;
                    case "fst":
                    case "fstp":
                        if (instr_params[0].type == PT.fpu_reg && instr_params[0].paramstr == "st(0)")
                        {
                            // do nothing
                        }
                        else
                        {
                            add_output_line("\t" ~ get_parameter_write_string(instr_params[0], PF.floattype) ~ get_fpu_reg_string(0, FF.read) ~ ";");
                        }

                        if (line.word[0] == "fstp")
                        {
                            current_state.fpu_index --;
                        }
                        break;
                    case "fstsw":
                    case "fnstsw":
                        if (instr_params[0].type == PT.register)
                        {
                            if (lines[current_line - 1].word[0] == "fcom" || lines[current_line - 1].word[0] == "fcomp" || lines[current_line - 1].word[0] == "fcompp" || lines[current_line - 1].word[0] == "ftst" || lines[current_line - 1].word[0] == "ficomp")
                            {
                                if (lines[current_line + 1].word[0] == "sahf")
                                {
                                    // do nothing

                                    if (!current_state.regs["eax"].used)
                                    {
                                        current_state.regs["eax"].trashed = true;
                                    }
                                    current_state.regs["eax"].value = "".idup;
                                }
                                else if ((lines[current_line + 1].word[0] == "xor" && lines[current_line + 2].word[0] == "sahf" && lines[current_line + 3].word[0] == "jnc") ||
                                         (lines[current_line + 1].word[0] == "mov" && lines[current_line + 2].word[0] == "xor" && lines[current_line + 3].word[0] == "sahf" && lines[current_line + 4].word[0] == "jnc") ||
                                         (lines[current_line + 1].word[0] == "mov" && lines[current_line + 2].word[0] == "fcomp" && lines[current_line + 3].word[0] == "fstsw" && lines[current_line + 4].word[0] == "xor" && lines[current_line + 5].word[0] == "sahf" && lines[current_line + 6].word[0] == "jnc") ||
                                         (lines[current_line + 1].word[0] == "mov" && lines[current_line + 2].word[0] == "sahf" && lines[current_line + 3].word[0] == "jc") ||
                                         (lines[current_line + 1].word[0] == "and" && (lines[current_line + 1].word[1] == "ah" || (lines[current_line + 1].word[1].length >= 3 && lines[current_line + 1].word[1][0..3] == "ah,") )) ||
                                         (lines[current_line + 1].word[0] == "and" && (lines[current_line + 1].word[1] == "eax" || (lines[current_line + 1].word[1].length >= 4 && lines[current_line + 1].word[1][0..4] == "eax,") ))
                                        )
                                {
                                    string compare_str;

                                    if (lines[current_line + 1].word[0] == "and")
                                    {
                                        analyze_parameters(substr_from_entry(lines[current_line + 1].line, 1, ' '));
                                        if ((instr_params[0].paramstr == "ah" && instr_params[1].paramstr == "1") || (instr_params[0].paramstr == "eax" && instr_params[1].paramstr == "0100h"))
                                        {
                                            // ok
                                        }
                                        else
                                        {
                                            input_error("unhandled fstsw instruction");
                                        }
                                    }

                                    if (lines[current_line - 1].word[0] == "fcom" || lines[current_line - 1].word[0] == "fcomp")
                                    {
                                        analyze_parameters(substr_from_entry(lines[current_line - 1].line, 1, ' '));

                                        if (lines[current_line - 1].word[0] == "fcomp")
                                        {
                                            current_state.fpu_index ++;
                                        }

                                        if (instr_params.length == 2)
                                        {
                                            consolidate_parameters_size(instr_params[0], instr_params[1]);
                                            input_error("unhandled jump - fcom parameters");
                                        }
                                        else
                                        {
                                            compare_str = "(" ~ get_fpu_reg_string(0, FF.read) ~ " < " ~ get_parameter_read_string(instr_params[0], PF.floattype) ~ ")";
                                        }

                                        if (lines[current_line - 1].word[0] == "fcomp")
                                        {
                                            current_state.fpu_index --;
                                        }
                                    }
                                    else if (lines[current_line - 1].word[0] == "fcompp")
                                    {
                                        compare_str = "(" ~ get_fpu_reg_string(-2, FF.read) ~ " < " ~ get_fpu_reg_string(-1, FF.read) ~ ")";
                                    }
                                    else
                                    {
                                        compare_str = "(" ~ get_fpu_reg_string(0, FF.read) ~ " < 0.0" ~ fpureg_datatype_suffix ~ ")";
                                    }


                                    add_output_line("\teax = " ~ ((current_state.regs["eax"].used)?"":"/*") ~ "(eax & 0xffff0000) |" ~ ((current_state.regs["eax"].used)?"":"*/") ~ " (" ~ compare_str ~ "?0x100:0);");

                                    current_state.regs["eax"].used = true;
                                    current_state.regs["eax"].value = "".idup;
                                }
                                else
                                {
                                    input_error("unhandled fstsw instruction");
                                }
                            }
                            else
                            {
                                input_error("unhandled fstsw instruction");
                            }
                        }
                        else
                        {
                            input_error("unhandled fstsw parameters");
                        }

                        break;
                    case "ftst":
                        get_fpu_reg_string(0, FF.read);
                        break;
                    case "fxch":
                        if (instr_params.length == 0)
                        {
                            string param0str = get_fpu_reg_string(0, FF.read);
                            string param1str = get_fpu_reg_string(1, FF.rw);
                            get_fpu_reg_string(0, FF.write);
                            add_output_line("\t{ " ~ fpureg_datatype_name ~ " tmp = " ~ param0str ~ "; " ~ param0str ~ " = " ~ param1str ~ "; " ~ param1str ~ " = tmp; }");
                        }
                        else if (instr_params.length == 1)
                        {
                            string param0str_read = get_parameter_read_string(instr_params[0], PF.floattype);
                            string param1str = get_fpu_reg_string(0, FF.rw);
                            string param0str_write = get_parameter_write_string(instr_params[0], PF.floattype);
                            add_output_line("\t{ " ~ fpureg_datatype_name ~ " tmp = " ~ param0str_read ~ "; " ~ param0str_write ~ param1str ~ "; " ~ param1str ~ " = tmp; }");
                        }
                        else
                        {
                            input_error("unhandled fxch parameters");
                        }
                        break;
                    default:
                        input_error("unhandled x87 instruction");
                        break;
                }


                // ignore for now
                current_line++;
                continue;
            }

        }
        else
        {
            // ignore assembler directive
            if (line.word[0] == ".386" ||
                line.word[0] == ".model" ||
                line.word[0] == "locals" ||
                line.word[0] == "public" ||
                line.word[0] == ".data" ||
                line.word[0] == ".code" ||
                line.word[0] == "include" ||
                line.word[0] == "extrn" ||
                line.word[0] == ".486" ||
                line.word[0] == "align"
               )
            {
                current_line++;
                continue;
            }

            // equ definition
            if (line.word[1] == "equ")
            {
                if (line.line == "d equ dword ptr" || line.line == "w equ word ptr" || line.line == "b equ byte ptr")
                {
                    current_line++;
                    continue;
                }
                if (is_constant_expression(substr_from_entry(line.line, 2, ' ')))
                {
                    constants.length++;
                    cur_const = &constants[constants.length - 1];
                    cur_const.name = line.line[0..line.line.indexOf(' ')].idup;
                    cur_const.value = line.line[line.line.indexOf("equ")+3..$].strip().idup;
                    cur_const.linenum = current_line;

                    cur_const = null;

                    current_line++;
                    continue;
                }

                input_error("Unknown ""equ""");
            }

            // structure definition
            if (line.word[1] == "struc" || line.word[1] == "union")
            {
                if (substr_from_entry_equal(line.line, 2, ' ', ""))
                {
                    structures.length++;
                    cur_struc = &structures[structures.length - 1];
                    cur_struc.name = line.line[0..line.line.indexOf(' ')].idup;
                    cur_struc.linenum = current_line;
                    cur_struc.size = 0;
                    cur_struc.isunion = (line.word[1] == "union");

                    in_struc = true;
                    current_line++;
                    continue;
                }
                input_error("Unknown struc definition");
            }

            // procedure definition
            if (line.word[1] == "proc")
            {
                if (substr_from_entry_equal(line.line, 2, ' ', "near") || substr_from_entry_equal(line.line, 2, ' ', "pascal") || substr_from_entry_equal(line.line, 2, ' ', ""))
                {
                    local_variables.length = 0;
                    local_labels.length = 0;

                    procedure_name = line.line[0..line.line.indexOf(' ')].idup;
                    procedure_linenum = current_line;

                    current_procedure = find_proc(procedure_name);

                    foreach (regname; regs_list)
                    {
                        if (!(regname in current_state.regs))
                        {
                            asm_reg new_reg;
                            current_state.regs[regname] = new_reg;
                        }
                        current_state.regs[regname].name = regname.idup;
                        current_state.regs[regname].value = regname.idup;
                        current_state.regs[regname].used = false;
                        current_state.regs[regname].read_unknown = false;
                        current_state.regs[regname].trashed = false;
                    }
                    current_state.fpu_regs.length = 0;
                    current_state.stack_value.length = 0;
                    current_state.stack_index = -1;
                    current_state.stack_max_index = -1;
                    current_state.fpu_index = 9;
                    current_state.fpu_max_index = 1;
                    current_state.fpu_min_index = 20;

                    string proc_type = "".idup;
                    string return_type = "".idup;
                    string arguments = "".idup;

                    fpureg_datatype = FPU_DT.DOUBLE;

                    if (current_input_file != null)
                    {
                        rounding_mode = current_input_file.rounding_mode;
                    }

                    if (current_procedure != null)
                    {
                        if (!current_procedure.public_proc)
                        {
                            proc_type = "static".idup;
                        }
                        else
                        {
                            proc_type = "extern \"C\"".idup;
                        }


                        if (current_procedure.rounding_mode != FPU_RC.NONE)
                        {
                            rounding_mode = current_procedure.rounding_mode;
                        }

                        if (current_procedure.fpureg_datatype != FPU_DT.NONE)
                        {
                            fpureg_datatype = current_procedure.fpureg_datatype;
                        }


                        if (current_procedure.return_reg != "")
                        {
                            return_type = "uint32_t".idup;
                        }

                        foreach (regname; current_procedure.input_regs_list.keys)
                        {
                            current_state.regs[regname].used = true;
                        }

                        foreach (regname; current_procedure.output_regs_list.keys)
                        {
                            current_state.regs[regname].used = true;
                        }

                        foreach (i; current_procedure.input_fpu_regs_list.keys.sort)
                        {
                            get_fpu_reg_string(-i, FF.read);
                            current_state.fpu_regs[-i].read_unknown = false;
                        }

                        foreach (i; current_procedure.output_fpu_regs_list.keys)
                        {
                            get_fpu_reg_string(-i, 0);
                        }

                        foreach (i; current_procedure.scratch_fpu_regs_list.keys)
                        {
                            get_fpu_reg_string(-i, 0);
                        }

                        foreach (argument; current_procedure.arguments)
                        {
                            string argument_str;
                            switch (argument.type)
                            {
                                case PPT.register:
                                    argument_str = "uint32_t ".idup ~ ((argument.output)?"&":"") ~ "_" ~ argument.name;
                                    break;
                                case PPT.fpu_reg:
                                    argument_str = "double ".idup ~ ((argument.output)?"&":"") ~ "_" ~ get_fpu_reg_string(argument.fpuindex, 0);
                                    break;
                                case PPT.variable:
                                    argument_str = ((argument.floatarg)?"float":"uint32_t").idup ~ " " ~ argument.name;
                                    break;
                                default:
                                    input_error("Unknown procedure parameter type");
                            }

                            if (arguments != "") arguments = arguments ~ ", ";
                            arguments = arguments ~ argument_str;
                        }
                    }

                    add_output_line(((proc_type == "")?"":proc_type ~ " ") ~ ((return_type == "")?"void":return_type) ~ " " ~ procedure_name ~ "(" ~ ((arguments == "")?"void":arguments) ~ ") {");

                    fpureg_datatype_suffix = (fpureg_datatype == FPU_DT.FLOAT)?"f":"";
                    fpureg_datatype_name = (fpureg_datatype == FPU_DT.FLOAT)?"float":"double";

                    in_proc = true;
                    current_line++;
                    continue;
                }
                input_error("Unknown proc definition");
            }

            // variable label definition
            if (line.word[1] == "label")
            {
                variables.length++;
                cur_var = &variables[variables.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.offset = 0;
                cur_var.numitems = 0;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = false;
                cur_var.argument = false;

                if (substr_from_entry_equal(line.line, 2, ' ', "dword"))
                {
                    cur_var.size = 4;
                    cur_var = null;
                    current_line++;
                    continue;
                }
                else if (substr_from_entry_equal(line.line, 2, ' ', "float"))
                {
                    cur_var.floattype = true;
                    cur_var.size = 4;
                    cur_var = null;
                    current_line++;
                    continue;
                }

                input_error("Unknown variable label definition");
            }

            // variable definition
            if (line.word[1] == "float" || line.word[1] == "dd" || line.word[1] == "dw" || line.word[1] == "db")
            {
                variables.length++;
                cur_var = &variables[variables.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.offset = 0;
                cur_var.numitems = 1;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = false;
                cur_var.argument = false;

                if (line.word[1] == "float")
                {
                    cur_var.size = 4;
                    cur_var.floattype = true;
                }
                else if (line.word[1] == "dd")
                {
                    cur_var.size = 4;
                }
                else if (line.word[1] == "dw")
                {
                    cur_var.size = 2;
                }
                else
                {
                    cur_var.size = 1;
                }

                if (substr_from_entry_equal(line.line, 3, ' ', ""))
                {
                    cur_var.numitems = 1;
                }
                else if (substr_from_entry_equal(line.line, 3, ' ', "dup(?)") || substr_from_entry_equal(line.line, 3, ' ', "dup(0)"))
                {
                    try
                    {
                        cur_var.numitems = to!int(str_entry(line.line, 2, ' '));
                    }
                    catch (Exception e)
                    {
                        cur_var.numitems = 2;
                        // ignore, for now?
                    }
                }
                else if (substr_from_entry(line.line, 3, ' ').indexOf(',') > 0)
                {
                    cur_var.numitems = 2;
                    // ignore exact number of items
                }
                else
                {
                    input_error("Unknown variable definition");
                }

                cur_var = null;

                current_line++;
                continue;
            }

            // variable struc definition
            if (line.word[1] != "" && find_struc(line.line[line.word[0].length+1..line.word[0].length+1+line.word[1].length]) != null) // line.word[1]
            {
                auto var_struct = find_struc(line.line[line.word[0].length+1..line.word[0].length+1+line.word[1].length]);

                variables.length++;
                cur_var = &variables[variables.length - 1];
                cur_var.name = line.line[0..line.line.indexOf(' ')].idup;
                cur_var.linenum = current_line;
                cur_var.size = var_struct.size;
                cur_var.offset = 0;
                cur_var.numitems = 1;
                cur_var.inttype = false;
                cur_var.floattype = false;
                cur_var.structype = true;
                cur_var.type_name = var_struct.name.idup;

                cur_var = null;

                if (substr_from_entry_equal(line.line, 2, ' ', "<?>") || substr_from_entry_equal(line.line, 2, ' ', "?"))
                {
                    current_line++;
                    continue;
                }

                input_error("Unknown variable struc definition");
            }

            // constant definition
            if (line.word[1] == "=")
            {
                if (is_constant_expression(substr_from_entry(line.line, 2, ' ')))
                {
                    constants.length++;
                    cur_const = &constants[constants.length - 1];
                    cur_const.name = line.line[0..line.line.indexOf(' ')].idup;
                    cur_const.value = line.line[line.line.indexOf('=')+1..$].strip().idup;
                    cur_const.linenum = current_line;

                    cur_const = null;

                    current_line++;
                    continue;
                }

                input_error("Unknown = value");
            }

            // anonymous variable definition
            if (line.word[0] == "dd" || line.word[0] == "dw" || line.word[0] == "db")
            {
                // ignore

                current_line++;
                continue;
            }

            // anonymous variable struc definition
            if (line.word[0] != "" && find_struc(line.line[0..line.word[0].length]) != null) // line.word[0]
            {
                // ignore

                current_line++;
                continue;
            }

            // end of file
            if (line.line.toLower() == "end")
            {
                current_line = maxlines;
                continue;
            }
        }

        input_error("Unknown line");

        current_line++;
    };
}

void main()
{
    read_procedure_file("procedures.txt");

    // fpu round: up
    //read_input_file("tracks.asm");
    //read_input_file("erz.asm");
    //read_input_file("credits.asm");
    //read_input_file("mese.asm");

    // fpu round: nearest
    //read_input_file("2deffect.asm");
    read_input_file("m2ppro.asm");
    //read_input_file("m2serv.asm");
    //read_input_file("m2sort.asm");
    //read_input_file("m2dotpro.asm");
    //read_input_file("m2tracks.asm");
    //read_input_file("m2pman.asm");

    // fpu round: up
    //read_input_file("m2pt.asm");
    //read_input_file("m2pttr.asm");
    //read_input_file("m2ptg.asm");
    //read_input_file("m2ptb.asm");
    //read_input_file("m2ptf.asm");
    //read_input_file("m2ptftr.asm");

    process_input_file();

    write_output_file("output.cc");
}

