/* SPDX-License-Identifier: MIT */
/*
 * gltest - headless GLES2 checks for grate on Tegra 2, using the same
 * shaders as wlroots' GLES2 renderer. Renders into a 64x64 FBO through
 * EGL on GBM and prints the pixels it reads back.
 *
 *   gltest [/dev/dri/card0]
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gbm.h>

#define W 64
#define H 64

static const char *vs_quad =
	"uniform mat3 proj;\n"
	"attribute vec2 pos;\n"
	"void main() {\n"
	"	gl_Position = vec4(vec3(pos, 1.0) * proj, 1.0);\n"
	"}\n";

static const char *fs_quad =
	"precision mediump float;\n"
	"uniform vec4 color;\n"
	"void main() { gl_FragColor = color; }\n";

static const char *vs_tex =
	"uniform mat3 proj;\n"
	"uniform mat3 tex_proj;\n"
	"attribute vec2 pos;\n"
	"varying vec2 v_texcoord;\n"
	"void main() {\n"
	"	vec3 pos3 = vec3(pos, 1.0);\n"
	"	gl_Position = vec4(pos3 * proj, 1.0);\n"
	"	v_texcoord = (pos3 * tex_proj).xy;\n"
	"}\n";

static const char *fs_tex =
	"precision mediump float;\n"
	"varying vec2 v_texcoord;\n"
	"uniform sampler2D tex;\n"
	"uniform float alpha;\n"
	"void main() { gl_FragColor = texture2D(tex, v_texcoord) * alpha; }\n";

static GLuint compile(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[512];
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "shader: %s\n", log);
		exit(1);
	}
	return s;
}

static GLuint program(const char *vs, const char *fs)
{
	GLuint p = glCreateProgram();
	GLint ok;

	glAttachShader(p, compile(GL_VERTEX_SHADER, vs));
	glAttachShader(p, compile(GL_FRAGMENT_SHADER, fs));
	glBindAttribLocation(p, 0, "pos");
	glLinkProgram(p);
	glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) {
		fprintf(stderr, "link failed\n");
		exit(1);
	}
	return p;
}

/* unit square (0..1) to clip space, like wlroots' projection */
static const GLfloat proj[9] = {
	2, 0, -1,
	0, 2, -1,
	0, 0, 1,
};
static const GLfloat ident[9] = {
	1, 0, 0,
	0, 1, 0,
	0, 0, 1,
};
static const GLfloat quad[8] = { 0, 0, 1, 0, 0, 1, 1, 1 };

static void probe(const char *what, int x, int y)
{
	unsigned char px[4];

	glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("%-28s (%2d,%2d) = %3u %3u %3u %3u\n", what, x, y,
	       px[0], px[1], px[2], px[3]);
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* full-screen BGRA uploads, like phoc updating a redrawn Phosh surface */
static void upload_bench(void)
{
	const int w = 1280, h = 800, n = 30;
	size_t size = (size_t)w * h * 4;
	unsigned char *src = malloc(size), *dst = malloc(size);
	GLuint tex;
	double t;
	int i;

	memset(src, 0x5a, size);
	memset(dst, 0, size);

	t = now();
	for (i = 0; i < n; i++)
		memcpy(dst, src, size);
	t = now() - t;
	printf("memcpy cached->cached   %6.1f ms/frame %6.0f MB/s\n",
	       t * 1000 / n, size * n / t / 1e6);

	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, w, h, 0, GL_BGRA_EXT,
		     GL_UNSIGNED_BYTE, NULL);
	glFinish();
	t = now();
	for (i = 0; i < n; i++)
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_BGRA_EXT,
				GL_UNSIGNED_BYTE, src);
	glFinish();
	t = now() - t;
	printf("glTexSubImage2D 1280x800 %6.1f ms/frame %6.0f MB/s\n",
	       t * 1000 / n, size * n / t / 1e6);

	/* compositing: that texture drawn over a full-screen target */
	{
		GLuint rt, fbo, p = program(vs_tex, fs_tex);
		int blend;

		glGenTextures(1, &rt);
		glBindTexture(GL_TEXTURE_2D, rt);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, w, h, 0, GL_BGRA_EXT,
			     GL_UNSIGNED_BYTE, NULL);
		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
				       GL_TEXTURE_2D, rt, 0);
		glViewport(0, 0, w, h);
		glBindTexture(GL_TEXTURE_2D, tex);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glUseProgram(p);
		glUniformMatrix3fv(glGetUniformLocation(p, "proj"), 1, GL_FALSE, proj);
		glUniformMatrix3fv(glGetUniformLocation(p, "tex_proj"), 1, GL_FALSE, ident);
		glUniform1i(glGetUniformLocation(p, "tex"), 0);
		glUniform1f(glGetUniformLocation(p, "alpha"), 1.0);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
		glEnableVertexAttribArray(0);
		glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		for (blend = 0; blend < 2; blend++) {
			if (blend)
				glEnable(GL_BLEND);
			else
				glDisable(GL_BLEND);
			glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			glFinish();
			t = now();
			for (i = 0; i < n; i++) {
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				glFinish();
			}
			t = now() - t;
			printf("composite 1280x800 %-5s  %6.1f ms/frame\n",
			       blend ? "over" : "copy", t * 1000 / n);
		}

		/* no texture: solid fill, full screen and 64x64 */
		GLuint q = program(vs_quad, fs_quad);
		glUseProgram(q);
		glUniformMatrix3fv(glGetUniformLocation(q, "proj"), 1, GL_FALSE, proj);
		glUniform4f(glGetUniformLocation(q, "color"), 0.2, 0.4, 0.6, 1.0);
		glDisable(GL_BLEND);
		for (blend = 0; blend < 2; blend++) {
			int vw = blend ? 64 : w, vh = blend ? 64 : h;

			glViewport(0, 0, vw, vh);
			glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			glFinish();
			t = now();
			for (i = 0; i < n; i++) {
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				glFinish();
			}
			t = now() - t;
			printf("solid fill %4dx%-4d      %6.1f ms/frame\n",
			       vw, vh, t * 1000 / n);
		}
		glViewport(0, 0, w, h);
	}
	free(src);
	free(dst);
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/dri/card0";
	int fd = open(node, O_RDWR | O_CLOEXEC);
	struct gbm_device *gbm;
	EGLDisplay dpy;
	EGLContext ctx;
	EGLint major, minor;
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	GLuint fbo, rt, tex, pq, pt;
	unsigned char texels[4 * 4 * 4];
	int i;

	if (fd < 0) {
		perror(node);
		return 1;
	}
	gbm = gbm_create_device(fd);
	dpy = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	if (!eglInitialize(dpy, &major, &minor)) {
		fprintf(stderr, "eglInitialize failed\n");
		return 1;
	}
	eglBindAPI(EGL_OPENGL_ES_API);
	ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ctx_attr);
	if (!ctx || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
		fprintf(stderr, "no surfaceless context\n");
		return 1;
	}
	printf("GL_RENDERER %s\n", glGetString(GL_RENDERER));

	/* BGRA render target, like a GBM scanout buffer */
	glGenTextures(1, &rt);
	glBindTexture(GL_TEXTURE_2D, rt);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, W, H, 0, GL_BGRA_EXT,
		     GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			       GL_TEXTURE_2D, rt, 0);
	printf("fbo status 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	glViewport(0, 0, W, H);

	glClearColor(0.0, 0.0, 1.0, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	probe("clear blue", 5, 5);

	/* grate's own fragment compiler: varying colour */
	{
		static const char *vs_col =
			"attribute vec2 pos;\n"
			"varying vec4 v_color;\n"
			"void main() {\n"
			"	gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);\n"
			"	v_color = vec4(0.0, 1.0, 0.0, 1.0);\n"
			"}\n";
		static const char *fs_col =
			"precision mediump float;\n"
			"varying vec4 v_color;\n"
			"void main() { gl_FragColor = v_color; }\n";
		GLuint pc = program(vs_col, fs_col);

		glUseProgram(pc);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
		glEnableVertexAttribArray(0);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
		probe("grate compiler: green", 5, 5);

		/* same with a depth buffer and depth test, like kmscube */
		GLuint rb;
		glGenRenderbuffers(1, &rb);
		glBindRenderbuffer(GL_RENDERBUFFER, rb);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, W, H);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
					  GL_RENDERBUFFER, rb);
		printf("fbo+depth status 0x%x\n",
		       glCheckFramebufferStatus(GL_FRAMEBUFFER));
		glEnable(GL_DEPTH_TEST);
		glDepthFunc(GL_LESS);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
		probe("grate compiler+depth: green", 5, 5);
		glDisable(GL_DEPTH_TEST);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
					  GL_RENDERBUFFER, 0);
	}

	/* solid quad, no blending */
	pq = program(vs_quad, fs_quad);
	glUseProgram(pq);
	glUniformMatrix3fv(glGetUniformLocation(pq, "proj"), 1, GL_FALSE, proj);
	glUniform4f(glGetUniformLocation(pq, "color"), 1.0, 0.0, 0.0, 1.0);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
	glEnableVertexAttribArray(0);
	glDisable(GL_BLEND);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("solid red", 5, 5);
	probe("solid red", 60, 60);

	/* scissor: left half, then bottom half (GL window coordinates) */
	glClear(GL_COLOR_BUFFER_BIT);
	glEnable(GL_SCISSOR_TEST);
	glScissor(0, 0, W / 2, H);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("scissor x: red", 5, 5);
	probe("scissor x: blue", 60, 5);
	glDisable(GL_SCISSOR_TEST);
	glClear(GL_COLOR_BUFFER_BIT);
	glEnable(GL_SCISSOR_TEST);
	glScissor(0, 0, W, H / 2);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("scissor y: red", 5, 5);
	probe("scissor y: blue", 5, 60);
	glDisable(GL_SCISSOR_TEST);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	/* solid quad, premultiplied over: 50% green over red */
	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	glUniform4f(glGetUniformLocation(pq, "color"), 0.0, 0.5, 0.0, 0.5);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("over: ~128 128 0 255", 5, 5);

	/* 4x4 texture: left half white, right half 50% grey (premultiplied) */
	for (i = 0; i < 16; i++) {
		unsigned char v = (i % 4) < 2 ? 255 : 64;
		unsigned char a = (i % 4) < 2 ? 255 : 128;
		texels[i * 4 + 0] = v;
		texels[i * 4 + 1] = (i / 4) < 2 ? v : 0;
		texels[i * 4 + 2] = v;
		texels[i * 4 + 3] = a;
	}
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, 4, 4, 0, GL_BGRA_EXT,
		     GL_UNSIGNED_BYTE, texels);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

	pt = program(vs_tex, fs_tex);
	glUseProgram(pt);
	glUniformMatrix3fv(glGetUniformLocation(pt, "proj"), 1, GL_FALSE, proj);
	glUniformMatrix3fv(glGetUniformLocation(pt, "tex_proj"), 1, GL_FALSE, ident);
	glUniform1i(glGetUniformLocation(pt, "tex"), 0);
	glUniform1f(glGetUniformLocation(pt, "alpha"), 1.0);

	glDisable(GL_BLEND);
	glClear(GL_COLOR_BUFFER_BIT);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("tex: white", 5, 5);
	probe("tex: grey 64 0 64 128", 60, 5);
	probe("tex: 255 0 255 255", 5, 60);

	glEnable(GL_BLEND);
	glClear(GL_COLOR_BUFFER_BIT);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("tex over blue: white", 5, 5);
	probe("tex over blue: 64 0 191 255", 60, 5);

	glUniform1f(glGetUniformLocation(pt, "alpha"), 0.5);
	glClear(GL_COLOR_BUFFER_BIT);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();
	probe("tex*0.5 over blue: 128 128 255", 5, 5);

	/* RGBX: texture alpha ignored */
	{
		static const char *fs_rgbx =
			"precision mediump float;\n"
			"varying vec2 v_texcoord;\n"
			"uniform sampler2D tex;\n"
			"uniform float alpha;\n"
			"void main() {\n"
			"	gl_FragColor = vec4(texture2D(tex, v_texcoord).rgb, 1.0) * alpha;\n"
			"}\n";
		GLuint px = program(vs_tex, fs_rgbx);

		glUseProgram(px);
		glUniformMatrix3fv(glGetUniformLocation(px, "proj"), 1, GL_FALSE, proj);
		glUniformMatrix3fv(glGetUniformLocation(px, "tex_proj"), 1, GL_FALSE, ident);
		glUniform1i(glGetUniformLocation(px, "tex"), 0);
		glUniform1f(glGetUniformLocation(px, "alpha"), 1.0);
		glDisable(GL_BLEND);
		glClear(GL_COLOR_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
		probe("rgbx: 64 64 64 255", 60, 5);
		glEnable(GL_BLEND);
		glUniform1f(glGetUniformLocation(px, "alpha"), 0.5);
		glClear(GL_COLOR_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
		probe("rgbx*0.5 over blue: 32 32 159 255", 60, 5);
		glUseProgram(pt);
	}

	printf("glGetError 0x%x\n", glGetError());

	if (argc > 2 && !strcmp(argv[2], "upload"))
		upload_bench();
	return 0;
}
