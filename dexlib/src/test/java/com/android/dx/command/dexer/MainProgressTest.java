package com.android.dx.command.dexer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;

public class MainProgressTest {
    @Test
    public void classPhaseReportsInitialMonotonicAndFinal() throws Exception {
        Path root = Files.createTempDirectory("jlmod-dx-progress-");
        Path jar = root.resolve("input.jar");
        Path dex = root.resolve("output.dex");
        try (JarOutputStream out = new JarOutputStream(Files.newOutputStream(jar))) {
            out.putNextEntry(new JarEntry("sample/Alpha.class"));
            out.write(createClass("sample/Alpha"));
            out.closeEntry();
            out.putNextEntry(new JarEntry("sample/Beta.class"));
            out.write(createClass("sample/Beta"));
            out.closeEntry();
            out.putNextEntry(new JarEntry("META-INF/NOT-A-CLASS.txt"));
            out.write(new byte[]{1, 2, 3});
            out.closeEntry();
        }

        List<int[]> events = new ArrayList<int[]>();
        Main.Arguments arguments = new Main.Arguments();
        arguments.fileNames = new String[]{jar.toString()};
        arguments.outName = dex.toString();
        arguments.numThreads = 1;
        ConversionResult result = Main.runWithResult(arguments,
                (completed, total) -> events.add(new int[]{completed, total}));

        assertTrue(result.isSuccess());
        assertEquals(2, result.getClassesDiscovered());
        assertTrue("expected initial (0,2) callback", events.size() >= 1
                && events.get(0)[0] == 0 && events.get(0)[1] == 2);
        int[] last = events.get(events.size() - 1);
        assertEquals(2, last[0]);
        assertEquals(2, last[1]);
        for (int i = 1; i < events.size(); i++) {
            assertTrue("progress must be monotonic",
                    events.get(i)[0] >= events.get(i - 1)[0]);
            assertEquals(2, events.get(i)[1]);
            assertTrue(events.get(i)[0] >= 0 && events.get(i)[0] <= 2);
        }
    }

    @Test
    public void skippedUnreadableClassesStillAdvanceProgress() throws Exception {
        Path root = Files.createTempDirectory("jlmod-dx-progress-skip-");
        Path jar = root.resolve("input.jar");
        Path dex = root.resolve("output.dex");
        try (JarOutputStream out = new JarOutputStream(Files.newOutputStream(jar))) {
            out.putNextEntry(new JarEntry("sample/Good.class"));
            out.write(createClass("sample/Good"));
            out.closeEntry();
            out.putNextEntry(new JarEntry("sample/Bad.class"));
            out.write(new byte[]{0, 1, 2, 3});
            out.closeEntry();
        }

        List<int[]> events = new ArrayList<int[]>();
        Main.Arguments arguments = new Main.Arguments();
        arguments.fileNames = new String[]{jar.toString()};
        arguments.outName = dex.toString();
        arguments.numThreads = 1;
        ConversionResult result = Main.runWithResult(arguments,
                (completed, total) -> events.add(new int[]{completed, total}));

        assertTrue(result.isSuccess());
        assertEquals(1, result.getClassesConverted());
        assertEquals(1, result.getClassesSkipped());
        assertTrue(events.size() >= 2);
        int[] last = events.get(events.size() - 1);
        assertEquals(2, last[0]);
        assertEquals(2, last[1]);
    }

    @Test
    public void nullListenerLeavesConversionUnchanged() throws Exception {
        Path root = Files.createTempDirectory("jlmod-dx-progress-null-");
        Path jar = root.resolve("input.jar");
        Path dex = root.resolve("output.dex");
        try (JarOutputStream out = new JarOutputStream(Files.newOutputStream(jar))) {
            out.putNextEntry(new JarEntry("sample/Only.class"));
            out.write(createClass("sample/Only"));
            out.closeEntry();
        }

        Main.Arguments arguments = new Main.Arguments();
        arguments.fileNames = new String[]{jar.toString()};
        arguments.outName = dex.toString();
        arguments.numThreads = 1;
        ConversionResult result = Main.runWithResult(arguments);
        assertTrue(result.isSuccess());
        assertEquals(1, result.getClassesConverted());
    }

    private static byte[] createClass(String internalName) {
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        writer.visit(Opcodes.V1_6, Opcodes.ACC_PUBLIC, internalName, null, "java/lang/Object", null);
        MethodVisitor init = writer.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
        init.visitCode();
        init.visitVarInsn(Opcodes.ALOAD, 0);
        init.visitMethodInsn(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
        init.visitInsn(Opcodes.RETURN);
        init.visitMaxs(1, 1);
        init.visitEnd();
        writer.visitEnd();
        return writer.toByteArray();
    }
}
