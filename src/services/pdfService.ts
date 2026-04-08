import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import { UserProfile, DailySummary, ScanResult } from '../types';
import { format } from 'date-fns';

export const generateHealthReport = async (
  profile: UserProfile,
  dailySummary: DailySummary | null,
  scans: ScanResult[]
) => {
  try {
    const doc = new jsPDF();
    const pageWidth = doc.internal.pageSize.getWidth();
    const margin = 20;

    // Header
    doc.setFontSize(24);
    doc.setTextColor(0, 0, 0);
    doc.setFont('helvetica', 'bold');
    doc.text('NutriSnap AI', margin, 30);
    
    doc.setFontSize(12);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(100, 100, 100);
    doc.text('Personal Health & Nutrition Report', margin, 38);
    doc.text(`Generated on: ${format(new Date(), 'PPP p')}`, margin, 44);

    // Horizontal Line
    doc.setDrawColor(230, 230, 230);
    doc.line(margin, 50, pageWidth - margin, 50);

    // Section 1: User Profile
    doc.setFontSize(16);
    doc.setTextColor(0, 0, 0);
    doc.setFont('helvetica', 'bold');
    doc.text('1. User Profile', margin, 65);

    const profileData = [
      ['Name', profile.displayName || 'N/A'],
      ['Height', `${profile.height} cm`],
      ['Weight', `${profile.weight} kg`],
      ['BMI', `${profile.bmi?.toFixed(1) || 'N/A'} (${profile.bodyType || 'Unknown'})`],
      ['Goal', profile.goal?.toUpperCase() || 'N/A'],
    ];

    autoTable(doc, {
      startY: 70,
      head: [['Field', 'Value']],
      body: profileData,
      theme: 'striped',
      headStyles: { fillColor: [46, 125, 50], textColor: 255 },
      margin: { left: margin, right: margin },
    });

    // Section 2: Nutrition Goals
    const nextY = (doc as any).lastAutoTable.finalY + 15;
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('2. Nutrition Goals', margin, nextY);

    const goalData = [
      ['Daily Calorie Limit', `${profile.calorieLimit} kcal`],
      ['Protein Goal', `${profile.proteinGoal}g (${profile.proteinPct || 0}%)`],
      ['Carbs Goal', `${profile.carbsGoal}g (${profile.carbsPct || 0}%)`],
      ['Fats Goal', `${profile.fatsGoal}g (${profile.fatsPct || 0}%)`],
    ];

    autoTable(doc, {
      startY: nextY + 5,
      head: [['Metric', 'Target']],
      body: goalData,
      theme: 'grid',
      headStyles: { fillColor: [25, 118, 210], textColor: 255 },
      margin: { left: margin, right: margin },
    });

    // Section 3: Today's Summary
    const summaryY = (doc as any).lastAutoTable.finalY + 15;
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text("3. Today's Progress", margin, summaryY);

    const currentSummary = [
      ['Calories Consumed', `${dailySummary?.totalCalories || 0} kcal`],
      ['Calories Remaining', `${Math.max(0, (profile.calorieLimit || 0) - (dailySummary?.totalCalories || 0))} kcal`],
      ['Water Intake', `${dailySummary?.totalWater || 0} ml`],
    ];

    autoTable(doc, {
      startY: summaryY + 5,
      head: [['Metric', 'Current Status']],
      body: currentSummary,
      theme: 'striped',
      headStyles: { fillColor: [211, 47, 47], textColor: 255 },
      margin: { left: margin, right: margin },
    });

    // Section 4: Recent Food Scans (Last 30 Days)
    doc.addPage();
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('4. Recent Food Scans (Last 30 Days)', margin, 30);

    const scanRows = scans
      .filter(scan => {
        const scanDate = new Date(scan.timestamp);
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        return scanDate >= thirtyDaysAgo;
      })
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
      .map(scan => [
        format(new Date(scan.timestamp), 'MMM d, h:mm a'),
        scan.foodName,
        `${scan.calories} kcal`,
        `${scan.protein}g P / ${scan.carbs}g C / ${scan.fats}g F`,
      ]);

    autoTable(doc, {
      startY: 35,
      head: [['Date', 'Food Item', 'Calories', 'Macros (P/C/F)']],
      body: scanRows,
      theme: 'grid',
      headStyles: { fillColor: [66, 66, 66], textColor: 255 },
      styles: { fontSize: 9 },
      margin: { left: margin, right: margin },
    });

    // Footer on each page
    const pageCount = (doc as any).internal.getNumberOfPages();
    for (let i = 1; i <= pageCount; i++) {
      doc.setPage(i);
      doc.setFontSize(10);
      doc.setTextColor(150, 150, 150);
      doc.text(
        `NutriSnap AI Health Report - Page ${i} of ${pageCount}`,
        pageWidth / 2,
        doc.internal.pageSize.getHeight() - 10,
        { align: 'center' }
      );
    }

    // Save the PDF
    const fileName = `NutriSnap_Health_Report_${format(new Date(), 'yyyy-MM-dd')}.pdf`;
    
    // Try to save
    try {
      doc.save(fileName);
    } catch (saveError) {
      console.error("doc.save failed, trying alternative:", saveError);
      // Alternative for some environments: open in new tab
      const blob = doc.output('blob');
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = fileName;
      link.click();
      URL.revokeObjectURL(url);
    }
  } catch (error) {
    console.error("Error in generateHealthReport:", error);
    throw error;
  }
};
