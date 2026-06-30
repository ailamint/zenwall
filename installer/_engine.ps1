# _engine.ps1 — shared Zenwall collage engine for the PowerShell installer.
# Dot-source this from a generator script:  . "$PSScriptRoot\_engine.ps1"
# It compiles the C# WallpaperEngine once to WallpaperEngine.dll next to itself.
#
# This is the same aspect-aware weighted-tiling engine as the web app, kept here
# so the Windows auto-rotation path needs no browser. Public surface:
#   [WallpaperEngine]::CreateZenWallpaper($wallDir, $outputPath)
#   [WallpaperEngine]::SetWallpaper($path)

$Assemblies = @("System.Drawing", "System.Windows.Forms")
$DllPath    = Join-Path $PSScriptRoot "WallpaperEngine.dll"

if (Test-Path $DllPath) {
    Add-Type -Path $DllPath
} else {
    Add-Type -ReferencedAssemblies $Assemblies -OutputAssembly $DllPath -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Collections.Generic;
using System.IO;
using System.Linq;

public class WallpaperEngine {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    private const int SPI_SETDESKWALLPAPER = 20;
    private const int SPIF_UPDATEINIFILE = 0x01;
    private const int SPIF_SENDWININICHANGE = 0x02;

    public static void SetWallpaper(string path) {
        SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
    }

    public static void CreateZenWallpaper(string wallDir, string outputPath) {
        SetProcessDPIAware();
        int screenWidth = Screen.PrimaryScreen.Bounds.Width;
        int screenHeight = Screen.PrimaryScreen.Bounds.Height;

        if (screenWidth < 1280 || screenHeight < 720) return;

        int gridRows = 7;
        int gridCols = 22;
        int outerPadding = 0;
        int innerPadding = 6;

        int cellWidth  = (screenWidth  - 2 * outerPadding - (gridCols - 1) * innerPadding) / gridCols;
        int cellHeight = (screenHeight - 2 * outerPadding - (gridRows - 1) * innerPadding) / gridRows;

        Bitmap canvas = new Bitmap(screenWidth, screenHeight);
        using (Graphics g = Graphics.FromImage(canvas)) {
            g.Clear(Color.FromArgb(15, 15, 20));
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;

            bool[,] grid = new bool[gridRows, gridCols];
            string[] extensions = { "*.jpg", "*.jpeg", "*.png", "*.bmp", "*.webp", "*.gif" };
            List<string> imageFiles = new List<string>();
            foreach (string ext in extensions) {
                imageFiles.AddRange(Directory.GetFiles(wallDir, ext));
            }

            if (imageFiles.Count == 0) return;

            Random rnd = new Random();
            imageFiles = imageFiles.OrderBy(x => rnd.Next()).ToList();

            int imageIdx = 0;
            int placementAttempts = 0;
            int maxAttempts = imageFiles.Count * 3;

            while (imageIdx < imageFiles.Count && placementAttempts < maxAttempts) {
                placementAttempts++;
                string imgPath = imageFiles[imageIdx];

                try {
                    using (Image img = Image.FromFile(imgPath)) {
                        float imageAspect = (float)img.Width / img.Height;

                        int chunkW, chunkH;
                        if (imageAspect < 0.8f) {
                            int[] ws = { 1, 1, 2 }; int[] hs = { 2, 3, 3 }; int[] weights = { 8, 6, 4 };
                            int i = GetWeightedRandom(weights, rnd);
                            chunkW = ws[i]; chunkH = hs[i];
                        } else if (imageAspect > 1.3f) {
                            int[] ws = { 2, 3, 4, 3 }; int[] hs = { 1, 1, 2, 2 }; int[] weights = { 8, 6, 4, 6 };
                            int i = GetWeightedRandom(weights, rnd);
                            chunkW = ws[i]; chunkH = hs[i];
                        } else {
                            int[] ws = { 1, 2, 2, 1 }; int[] hs = { 1, 2, 1, 2 }; int[] weights = { 5, 8, 4, 4 };
                            int i = GetWeightedRandom(weights, rnd);
                            chunkW = ws[i]; chunkH = hs[i];
                        }

                        var pos = FindBestPosition(grid, chunkW, chunkH, gridRows, gridCols, rnd);

                        if (pos == null) {
                            int[,] fallbacks;
                            if (imageAspect < 0.8f) fallbacks = new int[,] { {1,2}, {1,1}, {2,1} };
                            else if (imageAspect > 1.3f) fallbacks = new int[,] { {2,1}, {1,1}, {1,2} };
                            else fallbacks = new int[,] { {2,2}, {1,1}, {2,1}, {1,2} };

                            for (int f = 0; f < fallbacks.GetLength(0); f++) {
                                pos = FindBestPosition(grid, fallbacks[f,0], fallbacks[f,1], gridRows, gridCols, rnd);
                                if (pos != null) {
                                    chunkW = fallbacks[f,0]; chunkH = fallbacks[f,1];
                                    break;
                                }
                            }
                        }

                        if (pos != null) {
                            int row = pos.Item1;
                            int col = pos.Item2;
                            imageIdx++;

                            int w = chunkW * cellWidth + (chunkW - 1) * innerPadding;
                            int h = chunkH * cellHeight + (chunkH - 1) * innerPadding;

                            float aspectChunk = (float)w / h;
                            int newW, newH, offsetX, offsetY;

                            if (imageAspect > aspectChunk) {
                                newH = h;
                                newW = (int)(h * imageAspect);
                                offsetX = outerPadding + col * (cellWidth + innerPadding) - (newW - w) / 2;
                                offsetY = outerPadding + row * (cellHeight + innerPadding);
                            } else {
                                newW = w;
                                newH = (int)(w / imageAspect);
                                offsetX = outerPadding + col * (cellWidth + innerPadding);
                                offsetY = outerPadding + row * (cellHeight + innerPadding) - (newH - h) / 2;
                            }

                            g.SetClip(new Rectangle(outerPadding + col * (cellWidth + innerPadding), outerPadding + row * (cellHeight + innerPadding), w, h));
                            g.DrawImage(img, offsetX, offsetY, newW, newH);
                            g.ResetClip();

                            MarkOccupied(grid, chunkW, chunkH, row, col);
                        }
                    }
                } catch { imageIdx++; }
            }
        }
        canvas.Save(outputPath, ImageFormat.Png);
        canvas.Dispose();
    }

    private static int GetWeightedRandom(int[] weights, Random rnd) {
        int sum = weights.Sum();
        int r = rnd.Next(sum);
        for (int i = 0; i < weights.Length; i++) {
            if (r < weights[i]) return i;
            r -= weights[i];
        }
        return 0;
    }

    private static Tuple<int, int> FindBestPosition(bool[,] grid, int cw, int ch, int rows, int cols, Random rnd) {
        var positions = new List<Tuple<float, int, int>>();
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                if (Fits(grid, cw, ch, r, c, rows, cols)) {
                    int neighbors = 0;
                    for (int i = Math.Max(0, r - 1); i < Math.Min(rows, r + ch + 1); i++) {
                        for (int j = Math.Max(0, c - 1); j < Math.Min(cols, c + cw + 1); j++) {
                            if (grid[i, j]) neighbors++;
                        }
                    }
                    float score = neighbors - (r * 0.1f) - (c * 0.05f);
                    positions.Add(new Tuple<float, int, int>(score, r, c));
                }
            }
        }

        if (positions.Count > 0) {
            return positions.OrderByDescending(p => p.Item1).Take(5).OrderBy(x => rnd.Next()).Select(p => new Tuple<int, int>(p.Item2, p.Item3)).First();
        }
        return null;
    }

    private static bool Fits(bool[,] grid, int cw, int ch, int r, int c, int rows, int cols) {
        if (r + ch > rows || c + cw > cols) return false;
        for (int i = r; i < r + ch; i++) {
            for (int j = c; j < c + cw; j++) {
                if (grid[i, j]) return false;
            }
        }
        return true;
    }

    private static void MarkOccupied(bool[,] grid, int cw, int ch, int r, int c) {
        for (int i = r; i < r + ch; i++) {
            for (int j = c; j < c + cw; j++) {
                grid[i, j] = true;
            }
        }
    }
}
"@
    Add-Type -Path $DllPath
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
