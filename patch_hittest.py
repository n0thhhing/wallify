with open("src/platform/native.m", "r") as f:
    text = f.read()

text = text.replace("- (BOOL)isFlipped { return YES; }", "- (BOOL)isFlipped { return YES; }\n- (NSView *)hitTest:(NSPoint)point { return self; }")

with open("src/platform/native.m", "w") as f:
    f.write(text)
