import re
with open("src/platform/native.m", "r") as f:
    text = f.read()

swap_func = """
void wallify_swap_textures(int src, int dest) {
    if (src >= 0 && src < 32 && dest >= 0 && dest < 32) {
        id<MTLTexture> tmp = loaded_textures[dest];
        loaded_textures[dest] = loaded_textures[src];
        loaded_textures[src] = tmp;
    }
}
"""
text = text.replace("void wallify_load_texture", swap_func + "\nvoid wallify_load_texture")

with open("src/platform/native.m", "w") as f:
    f.write(text)
