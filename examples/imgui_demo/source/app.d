module gui.guimain;

import std.string;
import std.conv;

import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import derelict.imgui.imgui;
import imgui_glfw;
import imgui_demo;

GLFWwindow* window;
bool showDDemoWindow;
bool showOrgDemoWindow;

void main(string[] argv) {

	DerelictGL3.load();
	DerelictGLFW3.load();
	DerelictImgui.load();

	// Setup window
	window = initWindow("ImGui OpenGL3 example");
	if(!window) return;

	igCreateContext();

	// Setup ImGui binding
	igImplGlfwGL3_Init(window, true);
	igImplOpenGL3_Init("unused");

	ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

	// Main loop
	while (!glfwWindowShouldClose(window)) {
		glfwPollEvents();
		igImplOpenGL3_NewFrame();
		igImplGlfwGL3_NewFrame();
		igNewFrame();

		// contents
		if(igButton("RUN imgui_demo (D-lang version)")) showDDemoWindow = !showDDemoWindow;
		if(igButton("RUN imgui_demo (C++ version)")) showOrgDemoWindow = !showOrgDemoWindow;
		if(showDDemoWindow) {
			igSetNextWindowPos(ImVec2(660, 30), ImGuiCond_FirstUseEver);
			imgui_demo.igShowDemoWindow(&showDDemoWindow);
		}
		if(showOrgDemoWindow) {
			igSetNextWindowPos(ImVec2(650, 20), ImGuiCond_FirstUseEver);
			derelict.imgui.imgui.igShowDemoWindow(&showOrgDemoWindow);
		}

        // Rendering
		igRender();
        int display_w, display_h;
        glfwMakeContextCurrent(window);
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(clear_color.x, clear_color.y, clear_color.z, clear_color.w);
        glClear(GL_COLOR_BUFFER_BIT);
        igImplOpenGL3_RenderDrawData(igGetDrawData());

        glfwMakeContextCurrent(window);
        glfwSwapBuffers(window);
	}

    // Cleanup
    igImplOpenGL3_Shutdown();
    igImplGlfwGL3_Shutdown();
	igDestroyContext();

    glfwDestroyWindow(window);
    glfwTerminate();
}

GLFWwindow* initWindow(string title) {

	// Setup window
	glfwSetErrorCallback(&error_callback);
	if (!glfwInit())
		return null;
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
	auto window = glfwCreateWindow(1280, 720, title.toStringz(), null, null);
	glfwMakeContextCurrent(window);
	glfwSwapInterval(1); // Enable vsync
	glfwInit();

	DerelictGL3.reload();
	return window;
}

extern(C) nothrow void error_callback(int error, const(char)* description) {
	import std.stdio;
	import std.conv;
	try writefln("glfw err: %s ('%s')",error, to!string(description));
	catch(Throwable) {}
}
