namespace Eigenverft.Bootstrapper
{

        partial class MainForm
        {
            /// <summary>
            /// Required designer variable.
            /// </summary>
            private System.ComponentModel.IContainer components = null;

            /// <summary>
            /// Clean up any resources being used.
            /// </summary>
            /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
            protected override void Dispose(bool disposing)
            {
                if (disposing && (components != null))
                {
                    components.Dispose();
                }
                base.Dispose(disposing);
            }

            #region Windows Form Designer generated code

            /// <summary>
            /// Required method for Designer support - do not modify
            /// the contents of this method with the code editor.
            /// </summary>
            private void InitializeComponent()
            {
            this.MainPanel = new System.Windows.Forms.Panel();
            this.progressBarEx31 = new Eigenverft.Bootstrapper.ProgressBarEx3();
            this.MainPanel.SuspendLayout();
            this.SuspendLayout();
            // 
            // MainPanel
            // 
            this.MainPanel.BackgroundImage = global::Eigenverft.Bootstrapper.Properties.Resources.eigenverft_background_part_logo;
            this.MainPanel.BackgroundImageLayout = System.Windows.Forms.ImageLayout.None;
            this.MainPanel.Controls.Add(this.progressBarEx31);
            this.MainPanel.Dock = System.Windows.Forms.DockStyle.Fill;
            this.MainPanel.Location = new System.Drawing.Point(0, 0);
            this.MainPanel.Margin = new System.Windows.Forms.Padding(0);
            this.MainPanel.Name = "MainPanel";
            this.MainPanel.Size = new System.Drawing.Size(500, 320);
            this.MainPanel.TabIndex = 0;
            // 
            // progressBarEx31
            // 
            this.progressBarEx31.BackgroundTransparencyPercent = 50;
            this.progressBarEx31.BarBackgroundColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(122)))), ((int)(((byte)(26)))));
            this.progressBarEx31.BorderStyle = Eigenverft.Bootstrapper.ProgressBarEx3.BorderStyleEnum.None;
            this.progressBarEx31.CustomText = "Starting...";
            this.progressBarEx31.CustomTextColor = System.Drawing.Color.FromArgb(((int)(((byte)(10)))), ((int)(((byte)(27)))), ((int)(((byte)(48)))));
            this.progressBarEx31.CustomTextFont = new System.Drawing.Font("Segoe UI Semibold", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.progressBarEx31.GradientEndColor = System.Drawing.Color.FromArgb(((int)(((byte)(255)))), ((int)(((byte)(122)))), ((int)(((byte)(26)))));
            this.progressBarEx31.GradientStartColor = System.Drawing.Color.FromArgb(((int)(((byte)(10)))), ((int)(((byte)(27)))), ((int)(((byte)(48)))));
            this.progressBarEx31.Location = new System.Drawing.Point(8, 286);
            this.progressBarEx31.Maximum = 1000;
            this.progressBarEx31.Name = "progressBarEx31";
            this.progressBarEx31.Size = new System.Drawing.Size(485, 28);
            this.progressBarEx31.TabIndex = 2;
            // 
            // MainForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(500, 320);
            this.Controls.Add(this.MainPanel);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.None;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "MainForm";
            this.ShowInTaskbar = false;
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "Eigenverft Bootstrapper";
            this.TopMost = true;
            this.Shown += new System.EventHandler(this.MainForm_Shown);
            this.MainPanel.ResumeLayout(false);
            this.ResumeLayout(false);

            }

            #endregion

            private System.Windows.Forms.Panel MainPanel;
        private ProgressBarEx3 progressBarEx31;
    }
  
}

