import polib
import logging
import re
import shutil

def replace_plurality(text):
    def replace_match(match):
        num = int(match.group(1)) - 1
        options = match.group(2).split('|')
        
        if 0 <= num < len(options):
            return options[num]
        return options[-1]

    text = re.sub(r'\{(\d+):([^\}]+)\}', replace_match, text)
    return text

def extract_names_from_po(po_file):
    names_singular = {}
    names_plural = {}

    for entry in po_file:
        if entry.msgctxt and entry.msgctxt.startswith("STRINGS.NAMES."):
            key = entry.msgctxt.split(".")[-1]
            names_singular[key] = entry.msgstr
        elif entry.msgctxt and entry.msgctxt.startswith("STRINGS.NAMES_PLURAL."):
            key = entry.msgctxt.split(".")[-1]
            names_plural[key] = entry.msgstr

    return names_singular, names_plural

def replace_names_in_string(text, names_singular, names_plural, clear_names):
    def lower_singular_replace(match):
        prefix, key = match.groups()
        name = names_singular.get(key, key)
        if prefix:
            return f"{prefix}{name.lower()}"
        else:
            tokens = name.split("|")
            return (tokens[0] if len(tokens) > 0 else name).lower()
    
    def lower_plural_replace(match):
        prefix, key = match.groups()
        name = names_plural.get(key, key)
        if prefix:
            return f"{prefix}{name.lower()}"
        else:
            tokens = name.split("|")
            return (tokens[0] if len(tokens) > 0 else name).lower()
    
    def singular_replace(match):
        prefix, key = match.groups()
        name = names_singular.get(key, key)
        if prefix:
            return f"{prefix}{name}"
        else:
            tokens = name.split("|")
            return tokens[0] if len(tokens) > 0 else name
    
    def plural_replace(match):
        prefix, key = match.groups()
        name = names_plural.get(key, key)
        if prefix:
            return f"{prefix}{name}"
        else:
            tokens = name.split("|")
            return tokens[0] if len(tokens) > 0 else name
    
    def upper_singular_replace(match):
        prefix, key = match.groups()
        name = names_singular.get(key, key).upper()
        if prefix:
            return f"{prefix}{name.upper()}"
        else:
            tokens = name.split("|")
            return (tokens[0] if len(tokens) > 0 else name).upper()
    
    def upper_plural_replace(match):
        prefix, key = match.groups()
        name = names_plural.get(key, key).upper()
        if prefix:
            return f"{prefix}{name.upper()}"
        else:
            tokens = name.split("|")
            return (tokens[0] if len(tokens) > 0 else name).upper()
    if "{" in text and clear_names == False:
        text = re.sub(r'([?:#*%]?)\{name\.([_a-z0-9]+)\}', lower_singular_replace, text)
        text = re.sub(r'{name\.([_a-z0-9]+)\}', lower_singular_replace, text)
        text = re.sub(r'([?:#*%]?)\{name_multiple\.([_a-z0-9]+)\}', lower_plural_replace, text)
        text = re.sub(r'{name_multiple\.([_a-z0-9]+)\}', lower_plural_replace, text)
        
        text = re.sub(r'([?:#*%]?)\{Name\.([_a-z0-9]+)\}', singular_replace, text)
        text = re.sub(r'{Name\.([_a-z0-9]+)\}', singular_replace, text)
        text = re.sub(r'([?:#*%]?)\{Name_multiple\.([_a-z0-9]+)\}', plural_replace, text)
        text = re.sub(r'{Name_multiple\.([_a-z0-9]+)\}', plural_replace, text)
        
        text = re.sub(r'([?:#*%]?)\{NAME\.([_a-z0-9]+)\}', upper_singular_replace, text)
        text = re.sub(r'{NAME\.([_a-z0-9]+)\}', upper_singular_replace, text)
        text = re.sub(r'([?:#*%]?)\{NAME_MULTIPLE\.([_a-z0-9]+)\}', upper_plural_replace, text)
        text = re.sub(r'{NAME_MULTIPLE\.([_a-z0-9]+)\}', upper_plural_replace, text)
    elif clear_names:
        tokens = text.split("|")
        text = tokens[0] if tokens else text
    return text

def process_po_file(input_po_path, backup_path ):
    shutil.copy(input_po_path, backup_path)
    
    po_file = polib.pofile(input_po_path)
    names_singular, names_plural = extract_names_from_po(po_file)
    for entry in po_file:
        if entry.msgstr:
            entry.msgstr = replace_plurality(replace_names_in_string(entry.msgstr, names_singular, names_plural, bool(entry.msgctxt and entry.msgctxt.startswith("STRINGS.NAMES."))))
    
    po_file.save(input_po_path)

if __name__ == "__main__":
    input_path = "uk.po"
    output_path = "uk_org.po"
    process_po_file(input_path, output_path)
