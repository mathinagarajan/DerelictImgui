module imgui_glfw;

import derelict.imgui.imgui;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;

version(Windows) {
	import core.sys.windows.windows : HWND, HGLRC;
	mixin DerelictGLFW3_NativeBind;
}

// Data
GLFWwindow*  g_Window = null;
double       g_Time = 0.0f;
bool[5]      g_MouseJustPressed = [ false, false, false, false, false ];
GLFWcursor*[ImGuiMouseCursor_COUNT]  g_MouseCursors = null;


// Chain GLFW callbacks: our callbacks will call the user's previously installed callbacks, if any.
GLFWmousebuttonfun   g_PrevUserCallbackMousebutton = null;
GLFWscrollfun        g_PrevUserCallbackScroll = null;
GLFWkeyfun           g_PrevUserCallbackKey = null;
GLFWcharfun          g_PrevUserCallbackChar = null;

string g_GlslVersionString = "#version 130\n";
GLuint       g_FontTexture = 0;
int          g_ShaderHandle = 0, g_VertHandle = 0, g_FragHandle = 0;
int          g_AttribLocationTex = 0, g_AttribLocationProjMtx = 0;
int          g_AttribLocationPosition = 0, g_AttribLocationUV = 0, g_AttribLocationColor = 0;
uint         g_VboHandle = 0, /*g_VaoHandle = 0,*/ g_ElementsHandle = 0;

extern(C) nothrow const(char)* igImplGlfwGL3_GetClipboardText(void* user_data)
{
    return glfwGetClipboardString(cast(GLFWwindow*)user_data);
}

extern(C) nothrow void igImplGlfwGL3_SetClipboardText(void* user_data, const(char)* text)
{
    glfwSetClipboardString(cast(GLFWwindow*)user_data, text);
}

extern(C) nothrow void igImplGlfwGL3_MouseButtonCallback(GLFWwindow* window, int button, int action, int mods)
{
    if (g_PrevUserCallbackMousebutton != null)
        g_PrevUserCallbackMousebutton(window, button, action, mods);

    if (action == GLFW_PRESS && button >= 0 && button < 5)
        g_MouseJustPressed[button] = true;
}

extern(C) nothrow void igImplGlfwGL3_ScrollCallback(GLFWwindow* window, double xoffset, double yoffset)
{
    if (g_PrevUserCallbackScroll != null)
        g_PrevUserCallbackScroll(window, xoffset, yoffset);

    auto io = igGetIO();
    io.MouseWheelH += cast(float)xoffset;
    io.MouseWheel += cast(float)yoffset;
}

extern(C) nothrow void igImplGlfwGL3_KeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (g_PrevUserCallbackKey != null) 
        g_PrevUserCallbackKey(window, key, scancode, action, mods);

    auto io = igGetIO();
    if (action == GLFW_PRESS)
        io.KeysDown[key] = true;
    if (action == GLFW_RELEASE)
        io.KeysDown[key] = false;

    //(void)mods; // Modifiers are not reliable across systems
    io.KeyCtrl = io.KeysDown[GLFW_KEY_LEFT_CONTROL] || io.KeysDown[GLFW_KEY_RIGHT_CONTROL];
    io.KeyShift = io.KeysDown[GLFW_KEY_LEFT_SHIFT] || io.KeysDown[GLFW_KEY_RIGHT_SHIFT];
    io.KeyAlt = io.KeysDown[GLFW_KEY_LEFT_ALT] || io.KeysDown[GLFW_KEY_RIGHT_ALT];
    io.KeySuper = io.KeysDown[GLFW_KEY_LEFT_SUPER] || io.KeysDown[GLFW_KEY_RIGHT_SUPER];
}

extern(C) nothrow void igImplGlfwGL3_CharCallback(GLFWwindow* window, uint c)
{
    if (g_PrevUserCallbackChar != null)
        g_PrevUserCallbackChar(window, c);

    auto io = igGetIO();
    if (c > 0 && c < 0x10000)
        io.AddInputCharacter(cast(ushort)c);
}

bool igImplGlfwGL3_Init(GLFWwindow* window, bool install_callbacks)
{
    g_Window = window;
    g_Time = 0.0;

    // Setup back-end capabilities flags
    auto io = igGetIO();
    io.BackendFlags |= ImGuiBackendFlags_HasMouseCursors;         // We can honor GetMouseCursor() values (optional)
    io.BackendFlags |= ImGuiBackendFlags_HasSetMousePos;          // We can honor io.WantSetMousePos requests (optional, rarely used)

    // Keyboard mapping. ImGui will use those indices to peek into the io.KeysDown[] array.
    io.KeyMap[ImGuiKey_Tab] = GLFW_KEY_TAB;                         // Keyboard mapping. ImGui will use those indices to peek into the io.KeyDown[] array.
    io.KeyMap[ImGuiKey_LeftArrow] = GLFW_KEY_LEFT;
    io.KeyMap[ImGuiKey_RightArrow] = GLFW_KEY_RIGHT;
    io.KeyMap[ImGuiKey_UpArrow] = GLFW_KEY_UP;
    io.KeyMap[ImGuiKey_DownArrow] = GLFW_KEY_DOWN;
    io.KeyMap[ImGuiKey_PageUp] = GLFW_KEY_PAGE_UP;
    io.KeyMap[ImGuiKey_PageDown] = GLFW_KEY_PAGE_DOWN;
    io.KeyMap[ImGuiKey_Home] = GLFW_KEY_HOME;
    io.KeyMap[ImGuiKey_End] = GLFW_KEY_END;
    io.KeyMap[ImGuiKey_Delete] = GLFW_KEY_DELETE;
    io.KeyMap[ImGuiKey_Backspace] = GLFW_KEY_BACKSPACE;
    io.KeyMap[ImGuiKey_Enter] = GLFW_KEY_ENTER;
    io.KeyMap[ImGuiKey_Escape] = GLFW_KEY_ESCAPE;
    io.KeyMap[ImGuiKey_A] = GLFW_KEY_A;
    io.KeyMap[ImGuiKey_C] = GLFW_KEY_C;
    io.KeyMap[ImGuiKey_V] = GLFW_KEY_V;
    io.KeyMap[ImGuiKey_X] = GLFW_KEY_X;
    io.KeyMap[ImGuiKey_Y] = GLFW_KEY_Y;
    io.KeyMap[ImGuiKey_Z] = GLFW_KEY_Z;

    io.SetClipboardTextFn = &igImplGlfwGL3_SetClipboardText;
    io.GetClipboardTextFn = &igImplGlfwGL3_GetClipboardText;
    io.ClipboardUserData = g_Window;
    version( Windows ) {
		DerelictGLFW3_loadNative;
        io.ImeWindowHandle = glfwGetWin32Window(g_Window);
    }

    g_MouseCursors[ImGuiMouseCursor_Arrow] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);
    g_MouseCursors[ImGuiMouseCursor_TextInput] = glfwCreateStandardCursor(GLFW_IBEAM_CURSOR);
    g_MouseCursors[ImGuiMouseCursor_ResizeAll] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);   // FIXME: GLFW doesn't have this.
    g_MouseCursors[ImGuiMouseCursor_ResizeNS] = glfwCreateStandardCursor(GLFW_VRESIZE_CURSOR);
    g_MouseCursors[ImGuiMouseCursor_ResizeEW] = glfwCreateStandardCursor(GLFW_HRESIZE_CURSOR);
    g_MouseCursors[ImGuiMouseCursor_ResizeNESW] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);  // FIXME: GLFW doesn't have this.
    g_MouseCursors[ImGuiMouseCursor_ResizeNWSE] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);  // FIXME: GLFW doesn't have this.
    g_MouseCursors[ImGuiMouseCursor_Hand] = glfwCreateStandardCursor(GLFW_HAND_CURSOR);

    // Chain GLFW callbacks: our callbacks will call the user's previously installed callbacks, if any.
    g_PrevUserCallbackMousebutton = null;
    g_PrevUserCallbackScroll = null;
    g_PrevUserCallbackKey = null;
    g_PrevUserCallbackChar = null;
    if (install_callbacks)
    {
        g_PrevUserCallbackMousebutton = glfwSetMouseButtonCallback(window, &igImplGlfwGL3_MouseButtonCallback);
        g_PrevUserCallbackScroll = glfwSetScrollCallback(window, &igImplGlfwGL3_ScrollCallback);
        g_PrevUserCallbackKey = glfwSetKeyCallback(window, &igImplGlfwGL3_KeyCallback);
        g_PrevUserCallbackChar = glfwSetCharCallback(window, &igImplGlfwGL3_CharCallback);
    }

    return true;
}


void igImplGlfwGL3_Shutdown()
{
	for (ImGuiMouseCursor cursor_n = 0; cursor_n < ImGuiMouseCursor_COUNT; cursor_n++)
    {
        glfwDestroyCursor(g_MouseCursors[cursor_n]);
        g_MouseCursors[cursor_n] = null;
    }
}


void igImplGlfw_UpdateMousePosAndButtons()
{
    // Update buttons
    auto io = igGetIO();
    for (int i = 0; i < 5; i++)
    {
        // If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
        io.MouseDown[i] = g_MouseJustPressed[i] || glfwGetMouseButton(g_Window, i) != 0;
        g_MouseJustPressed[i] = false;
    }

    // Update mouse position
    const ImVec2 mouse_pos_backup = io.MousePos;
    io.MousePos = ImVec2(-float.max, -float.max);
    const bool focused = glfwGetWindowAttrib(g_Window, GLFW_FOCUSED) != 0;
    if (focused)
    {
        if (io.WantSetMousePos)
        {
            glfwSetCursorPos(g_Window, cast(double)mouse_pos_backup.x, cast(double)mouse_pos_backup.y);
        }
        else
        {
            double mouse_x, mouse_y;
            glfwGetCursorPos(g_Window, &mouse_x, &mouse_y);
            io.MousePos = ImVec2(cast(float)mouse_x, cast(float)mouse_y);
        }
    }
}

void igImplGlfw_UpdateMouseCursor()
{
    auto io = igGetIO();
    if ((io.ConfigFlags & ImGuiConfigFlags_NoMouseCursorChange) || glfwGetInputMode(g_Window, GLFW_CURSOR) == GLFW_CURSOR_DISABLED)
        return;

    ImGuiMouseCursor imgui_cursor = igGetMouseCursor();
    if (imgui_cursor == ImGuiMouseCursor_None || io.MouseDrawCursor)
    {
        // Hide OS mouse cursor if imgui is drawing it or if it wants no cursor
        glfwSetInputMode(g_Window, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    }
    else
    {
        // Show OS mouse cursor
        // FIXME-PLATFORM: Unfocused windows seems to fail changing the mouse cursor with GLFW 3.2, but 3.3 works here.
        glfwSetCursor(g_Window, g_MouseCursors[imgui_cursor] ? g_MouseCursors[imgui_cursor] : g_MouseCursors[ImGuiMouseCursor_Arrow]);
        glfwSetInputMode(g_Window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    }
}


void igImplGlfwGL3_NewFrame()
{
    auto io = igGetIO();
    assert(io.Fonts.IsBuilt());     // Font atlas needs to be built, call renderer _NewFrame() function e.g. ImGui_ImplOpenGL3_NewFrame() 

    // Setup display size
    int w, h;
    int display_w, display_h;
    glfwGetWindowSize(g_Window, &w, &h);
    glfwGetFramebufferSize(g_Window, &display_w, &display_h);
    io.DisplaySize = ImVec2(cast(float)w, cast(float)h);
    io.DisplayFramebufferScale = ImVec2(w > 0 ? (cast(float)display_w / w) : 0, h > 0 ? (cast(float)display_h / h) : 0);

    // Setup time step
    double current_time = glfwGetTime();
    io.DeltaTime = g_Time > 0.0 ? cast(float)(current_time - g_Time) : cast(float)(1.0f/60.0f);
    g_Time = current_time;

    igImplGlfw_UpdateMousePosAndButtons();
    igImplGlfw_UpdateMouseCursor();

	//// Gamepad navigation mapping [BETA]
	//memset(io.NavInputs, 0, sizeof(io.NavInputs));
	//if (io.ConfigFlags & ImGuiConfigFlags_NavEnableGamepad)
	//{
	//    // Update gamepad inputs
	//    #define MAP_BUTTON(NAV_NO, BUTTON_NO)       { if (buttons_count > BUTTON_NO && buttons[BUTTON_NO] == GLFW_PRESS) io.NavInputs[NAV_NO] = 1.0f; }
	//    #define MAP_ANALOG(NAV_NO, AXIS_NO, V0, V1) { float v = (axes_count > AXIS_NO) ? axes[AXIS_NO] : V0; v = (v - V0) / (V1 - V0); if (v > 1.0f) v = 1.0f; if (io.NavInputs[NAV_NO] < v) io.NavInputs[NAV_NO] = v; }
	//    int axes_count = 0, buttons_count = 0;
	//    const float* axes = glfwGetJoystickAxes(GLFW_JOYSTICK_1, &axes_count);
	//    const unsigned char* buttons = glfwGetJoystickButtons(GLFW_JOYSTICK_1, &buttons_count);
	//    MAP_BUTTON(ImGuiNavInput_Activate,   0);     // Cross / A
	//    MAP_BUTTON(ImGuiNavInput_Cancel,     1);     // Circle / B
	//    MAP_BUTTON(ImGuiNavInput_Menu,       2);     // Square / X
	//    MAP_BUTTON(ImGuiNavInput_Input,      3);     // Triangle / Y
	//    MAP_BUTTON(ImGuiNavInput_DpadLeft,   13);    // D-Pad Left
	//    MAP_BUTTON(ImGuiNavInput_DpadRight,  11);    // D-Pad Right
	//    MAP_BUTTON(ImGuiNavInput_DpadUp,     10);    // D-Pad Up
	//    MAP_BUTTON(ImGuiNavInput_DpadDown,   12);    // D-Pad Down
	//    MAP_BUTTON(ImGuiNavInput_FocusPrev,  4);     // L1 / LB
	//    MAP_BUTTON(ImGuiNavInput_FocusNext,  5);     // R1 / RB
	//    MAP_BUTTON(ImGuiNavInput_TweakSlow,  4);     // L1 / LB
	//    MAP_BUTTON(ImGuiNavInput_TweakFast,  5);     // R1 / RB
	//    MAP_ANALOG(ImGuiNavInput_LStickLeft, 0,  -0.3f,  -0.9f);
	//    MAP_ANALOG(ImGuiNavInput_LStickRight,0,  +0.3f,  +0.9f);
	//    MAP_ANALOG(ImGuiNavInput_LStickUp,   1,  +0.3f,  +0.9f);
	//    MAP_ANALOG(ImGuiNavInput_LStickDown, 1,  -0.3f,  -0.9f);
	//    #undef MAP_BUTTON
	//    #undef MAP_ANALOG
	//    if (axes_count > 0 && buttons_count > 0)
	//        io.BackendFlags |= ImGuiBackendFlags_HasGamepad;
	//    else
	//        io.BackendFlags &= ~ImGuiBackendFlags_HasGamepad;
	//}
}

bool    igImplOpenGL3_Init(const(char)* glsl_version)
{
	// assume version 130
	return true;
}


void igImplOpenGL3_Shutdown()
{
    igImplOpenGL3_DestroyDeviceObjects();
}

void igImplOpenGL3_NewFrame()
{
    if (!g_FontTexture)
        igImplOpenGL3_CreateDeviceObjects();
}

// OpenGL3 Render function.
// (this used to be set in io.RenderDrawListsFn and called by ImGui::Render(), but you can now call this directly from your main loop)
// Note that this implementation is little overcomplicated because we are saving/setting up/restoring every OpenGL state explicitly, in order to be able to run within any OpenGL engine that doesn't do so.
void igImplOpenGL3_RenderDrawData(ImDrawData* draw_data)
{
    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    auto io = igGetIO();
    int fb_width = cast(int)(io.DisplaySize.x * io.DisplayFramebufferScale.x);
    int fb_height = cast(int)(io.DisplaySize.y * io.DisplayFramebufferScale.y);
    if (fb_width == 0 || fb_height == 0)
        return;
    draw_data.ScaleClipRects(io.DisplayFramebufferScale);

    // Backup GL state
    GLenum last_active_texture; glGetIntegerv(GL_ACTIVE_TEXTURE, cast(GLint*)&last_active_texture);
    glActiveTexture(GL_TEXTURE0);
    GLint last_program; glGetIntegerv(GL_CURRENT_PROGRAM, &last_program);
    GLint last_texture; glGetIntegerv(GL_TEXTURE_BINDING_2D, &last_texture);
    GLint last_array_buffer; glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &last_array_buffer);
    GLint last_vertex_array; glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &last_vertex_array);
    GLint[4] last_viewport; glGetIntegerv(GL_VIEWPORT, last_viewport.ptr);
    GLint[4] last_scissor_box; glGetIntegerv(GL_SCISSOR_BOX, last_scissor_box.ptr);
    GLenum last_blend_src_rgb; glGetIntegerv(GL_BLEND_SRC_RGB, cast(GLint*)&last_blend_src_rgb);
    GLenum last_blend_dst_rgb; glGetIntegerv(GL_BLEND_DST_RGB, cast(GLint*)&last_blend_dst_rgb);
    GLenum last_blend_src_alpha; glGetIntegerv(GL_BLEND_SRC_ALPHA, cast(GLint*)&last_blend_src_alpha);
    GLenum last_blend_dst_alpha; glGetIntegerv(GL_BLEND_DST_ALPHA, cast(GLint*)&last_blend_dst_alpha);
    GLenum last_blend_equation_rgb; glGetIntegerv(GL_BLEND_EQUATION_RGB, cast(GLint*)&last_blend_equation_rgb);
    GLenum last_blend_equation_alpha; glGetIntegerv(GL_BLEND_EQUATION_ALPHA, cast(GLint*)&last_blend_equation_alpha);
    GLboolean last_enable_blend = glIsEnabled(GL_BLEND);
    GLboolean last_enable_cull_face = glIsEnabled(GL_CULL_FACE);
    GLboolean last_enable_depth_test = glIsEnabled(GL_DEPTH_TEST);
    GLboolean last_enable_scissor_test = glIsEnabled(GL_SCISSOR_TEST);

    // Setup render state: alpha-blending enabled, no face culling, no depth testing, scissor enabled
    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_SCISSOR_TEST);

    // Setup viewport, orthographic projection matrix
    // Our visible imgui space lies from draw_data->DisplayPos (top left) to draw_data->DisplayPos+data_data->DisplaySize (bottom right). DisplayMin is typically (0,0) for single viewport apps.
    glViewport(0, 0, cast(GLsizei)fb_width, cast(GLsizei)fb_height);
	float L = draw_data.DisplayPos.x;
    float R = draw_data.DisplayPos.x + draw_data.DisplaySize.x;
    float T = draw_data.DisplayPos.y;
    float B = draw_data.DisplayPos.y + draw_data.DisplaySize.y;
    const float[4][4] ortho_projection =
    [
        [ 2.0f/(R-L),            0.0f,                   0.0f, 0.0f ],
        [ 0.0f,                  2.0f/(T-B),             0.0f, 0.0f ],
        [ 0.0f,                  0.0f,                  -1.0f, 0.0f ],
        [(R+L)/(L-R),            (T+B)/(B-T),            0.0f, 1.0f ],
    ];
    glUseProgram(g_ShaderHandle);
    glUniform1i(g_AttribLocationTex, 0);
    glUniformMatrix4fv(g_AttribLocationProjMtx, 1, GL_FALSE, &ortho_projection[0][0]);

	// Recreate the VAO every time
    // (This is to easily allow multiple GL contexts. VAO are not shared among GL contexts, and we don't track creation/deletion of windows so we don't have an obvious key to use to cache them.)
    GLuint vao_handle = 0;
    glGenVertexArrays(1, &vao_handle);
    glBindVertexArray(vao_handle);
    glBindBuffer(GL_ARRAY_BUFFER, g_VboHandle);
    glEnableVertexAttribArray(g_AttribLocationPosition);
    glEnableVertexAttribArray(g_AttribLocationUV);
    glEnableVertexAttribArray(g_AttribLocationColor);
    glVertexAttribPointer(g_AttribLocationPosition, 2, GL_FLOAT, GL_FALSE, ImDrawVert.sizeof, cast(GLvoid*)ImDrawVert.pos.offsetof);
    glVertexAttribPointer(g_AttribLocationUV, 2, GL_FLOAT, GL_FALSE, ImDrawVert.sizeof, cast(GLvoid*)ImDrawVert.uv.offsetof);
    glVertexAttribPointer(g_AttribLocationColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, ImDrawVert.sizeof, cast(GLvoid*)ImDrawVert.col.offsetof);

    ImVec2 pos = draw_data.DisplayPos;
    for (int n = 0; n < draw_data.CmdListsCount; n++)
    {
        const(ImDrawList)* cmd_list = draw_data.CmdLists[n];
        const(ImDrawIdx)* idx_buffer_offset;

        auto countVertices = cmd_list.VtxBuffer.Size;
        glBindBuffer(GL_ARRAY_BUFFER, g_VboHandle);
        glBufferData(GL_ARRAY_BUFFER, countVertices * ImDrawVert.sizeof, cast(GLvoid*)(cmd_list.VtxBuffer.Data), GL_STREAM_DRAW);

        auto countIndices = cmd_list.IdxBuffer.Size;
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, g_ElementsHandle);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, countIndices * ImDrawIdx.sizeof, cast(GLvoid*)(cmd_list.IdxBuffer.Data), GL_STREAM_DRAW);

        auto cmdCnt = cmd_list.CmdBuffer.Size;

        foreach(cmd_i; 0..cmdCnt)
        {
            auto pcmd = cmd_list.CmdBuffer[cmd_i];

            if (pcmd.UserCallback)
            {
                // User callback (registered via ImDrawList::AddCallback)
                pcmd.UserCallback(cmd_list, &pcmd);
            }
            else
            {
                ImVec4 clip_rect = ImVec4(pcmd.ClipRect.x - pos.x, pcmd.ClipRect.y - pos.y, pcmd.ClipRect.z - pos.x, pcmd.ClipRect.w - pos.y);
                if (clip_rect.x < fb_width && clip_rect.y < fb_height && clip_rect.z >= 0.0f && clip_rect.w >= 0.0f)
                {
                    // Apply scissor/clipping rectangle
					glScissor(cast(int)pcmd.ClipRect.x, cast(int)(fb_height - pcmd.ClipRect.w), cast(int)(pcmd.ClipRect.z - pcmd.ClipRect.x), cast(int)(pcmd.ClipRect.w - pcmd.ClipRect.y));

                    // Bind texture, Draw
					glBindTexture(GL_TEXTURE_2D, cast(GLuint)pcmd.TextureId);
					glDrawElements(GL_TRIANGLES, cast(GLsizei)pcmd.ElemCount, ImDrawIdx.sizeof == 2 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT, idx_buffer_offset);
                }
            }
            idx_buffer_offset += pcmd.ElemCount;
        }
    }
	glDeleteVertexArrays(1, &vao_handle);


    // Restore modified GL state
    glUseProgram(last_program);
    glBindTexture(GL_TEXTURE_2D, last_texture);
    glActiveTexture(last_active_texture);
    glBindVertexArray(last_vertex_array);
    glBindBuffer(GL_ARRAY_BUFFER, last_array_buffer);
    glBlendEquationSeparate(last_blend_equation_rgb, last_blend_equation_alpha);
    glBlendFuncSeparate(last_blend_src_rgb, last_blend_dst_rgb, last_blend_src_alpha, last_blend_dst_alpha);
    if (last_enable_blend) glEnable(GL_BLEND); else glDisable(GL_BLEND);
    if (last_enable_cull_face) glEnable(GL_CULL_FACE); else glDisable(GL_CULL_FACE);
    if (last_enable_depth_test) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
    if (last_enable_scissor_test) glEnable(GL_SCISSOR_TEST); else glDisable(GL_SCISSOR_TEST);
    glViewport(last_viewport[0], last_viewport[1], cast(GLsizei)last_viewport[2], cast(GLsizei)last_viewport[3]);
    glScissor(last_scissor_box[0], last_scissor_box[1], cast(GLsizei)last_scissor_box[2], cast(GLsizei)last_scissor_box[3]);
}




bool igImplOpenGL3_CreateFontsTexture()
{
    // Build texture atlas
    auto io = igGetIO();
    char* pixels;
    int width, height;
    io.Fonts.GetTexDataAsRGBA32(&pixels, &width, &height);   // Load as RGBA 32-bits (75% of the memory is wasted, but default font is so small) because it is more likely to be compatible with user's existing shaders. If your ImTextureId represent a higher-level concept than just a GL texture id, consider calling GetTexDataAsAlpha8() instead to save on GPU memory.

    // Upload texture to graphics system
    GLint last_texture;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &last_texture);
    glGenTextures(1, &g_FontTexture);
    glBindTexture(GL_TEXTURE_2D, g_FontTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    // Store our identifier
    io.Fonts.TexID = cast(void*)g_FontTexture;

    // Restore state
    glBindTexture(GL_TEXTURE_2D, last_texture);

    return true;
}

void igImplOpenGL3_DestroyFontsTexture()
{
	if (g_FontTexture)
    {
		auto io = igGetIO();
        glDeleteTextures(1, &g_FontTexture);
        io.Fonts.TexID = null;
        g_FontTexture = 0;
    }
}

bool igImplOpenGL3_CreateDeviceObjects()
{
    // Backup GL state
    GLint last_texture, last_array_buffer, last_vertex_array;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &last_texture);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &last_array_buffer);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &last_vertex_array);

	const GLchar* vertex_shader =
		"#version 130\n" ~
        "uniform mat4 ProjMtx;\n" ~
        "in vec2 Position;\n" ~
        "in vec2 UV;\n" ~
        "in vec4 Color;\n" ~
        "out vec2 Frag_UV;\n" ~
        "out vec4 Frag_Color;\n" ~
        "void main()\n" ~
        "{\n" ~
        "    Frag_UV = UV;\n" ~
        "    Frag_Color = Color;\n" ~
        "    gl_Position = ProjMtx * vec4(Position.xy,0,1);\n" ~
        "}\n";

    const GLchar* fragment_shader =
		"#version 130\n" ~
        "uniform sampler2D Texture;\n" ~
        "in vec2 Frag_UV;\n" ~
        "in vec4 Frag_Color;\n" ~
        "out vec4 Out_Color;\n" ~
        "void main()\n" ~
        "{\n" ~
        "    Out_Color = Frag_Color * texture(Texture, Frag_UV.st);\n" ~
        "}\n";

    g_ShaderHandle = glCreateProgram();
    g_VertHandle = glCreateShader(GL_VERTEX_SHADER);
    g_FragHandle = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(g_VertHandle, 1, &vertex_shader, null);
    glShaderSource(g_FragHandle, 1, &fragment_shader, null);
    glCompileShader(g_VertHandle);
    glCompileShader(g_FragHandle);
    glAttachShader(g_ShaderHandle, g_VertHandle);
    glAttachShader(g_ShaderHandle, g_FragHandle);
    glLinkProgram(g_ShaderHandle);

    g_AttribLocationTex = glGetUniformLocation(g_ShaderHandle, "Texture");
    g_AttribLocationProjMtx = glGetUniformLocation(g_ShaderHandle, "ProjMtx");
    g_AttribLocationPosition = glGetAttribLocation(g_ShaderHandle, "Position");
    g_AttribLocationUV = glGetAttribLocation(g_ShaderHandle, "UV");
    g_AttribLocationColor = glGetAttribLocation(g_ShaderHandle, "Color");

    glGenBuffers(1, &g_VboHandle);
    glGenBuffers(1, &g_ElementsHandle);

    igImplOpenGL3_CreateFontsTexture();

    // Restore modified GL state
    glBindTexture(GL_TEXTURE_2D, last_texture);
    glBindBuffer(GL_ARRAY_BUFFER, last_array_buffer);
    glBindVertexArray(last_vertex_array);

    return true;
}

void igImplOpenGL3_DestroyDeviceObjects()
{
    if (g_VboHandle) glDeleteBuffers(1, &g_VboHandle);
    if (g_ElementsHandle) glDeleteBuffers(1, &g_ElementsHandle);
    g_VboHandle = g_ElementsHandle = 0;

    if (g_ShaderHandle && g_VertHandle) glDetachShader(g_ShaderHandle, g_VertHandle);
    if (g_VertHandle) glDeleteShader(g_VertHandle);
    g_VertHandle = 0;

    if (g_ShaderHandle && g_FragHandle) glDetachShader(g_ShaderHandle, g_FragHandle);
    if (g_FragHandle) glDeleteShader(g_FragHandle);
    g_FragHandle = 0;

    if (g_ShaderHandle) glDeleteProgram(g_ShaderHandle);
    g_ShaderHandle = 0;

	igImplOpenGL3_DestroyFontsTexture();
}


