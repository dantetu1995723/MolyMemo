import SwiftUI

// MARK: - 年视图（纯 SwiftUI 实现，无动画直接定位）
struct YearCalendarView: View {
    @Binding var currentMonth: Date
    @Binding var isPresented: Bool
    
    private let years = Array(1900...2100)
    private let calendar = Calendar.current
    
    // 静态缓存今天信息
    private static let todayInfo: (year: Int, month: Int, day: Int) = {
        let cal = Calendar.current
        let now = Date()
        return (cal.component(.year, from: now), cal.component(.month, from: now), cal.component(.day, from: now))
    }()
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 40) {
                    ForEach(years, id: \.self) { year in
                        YearSection(year: year, todayInfo: Self.todayInfo) { date in
                            currentMonth = date
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        .id(year)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
            }
            .background(Color.white)
            .onAppear {
                // 无动画直接定位
                let targetYear = calendar.component(.year, from: currentMonth)
                proxy.scrollTo(targetYear, anchor: .top)
            }
        }
    }
}

// MARK: - 年份区块
private struct YearSection: View {
    let year: Int
    let todayInfo: (year: Int, month: Int, day: Int)
    let onMonthSelected: (Date) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题行
            HStack {
                Text("\(String(year))年")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                Text("— \(lunarYear)\(zodiac)年")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 4)
            
            // 月份网格
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(1...12, id: \.self) { month in
                    MonthMini(year: year, month: month, todayInfo: todayInfo)
                        .onTapGesture {
                            if let date = Calendar.current.date(from: DateComponents(year: year, month: month)) {
                                onMonthSelected(date)
                            }
                        }
                }
            }
        }
    }
    
    private var zodiac: String {
        ["猴", "鸡", "狗", "猪", "鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊"][year % 12]
    }
    
    private var lunarYear: String {
        let stems = ["庚", "辛", "壬", "癸", "甲", "乙", "丙", "丁", "戊", "己"]
        let branches = ["申", "酉", "戌", "亥", "子", "丑", "寅", "卯", "辰", "巳", "午", "未"]
        return "\(stems[year % 10])\(branches[year % 12])"
    }
}

// MARK: - 月份迷你视图
private struct MonthMini: View {
    let year: Int
    let month: Int
    let todayInfo: (year: Int, month: Int, day: Int)
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    
    private var isCurrentMonth: Bool {
        todayInfo.year == year && todayInfo.month == month
    }
    
    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Calendar.current.date(from: DateComponents(year: year, month: month))!)?.count ?? 30
    }
    
    private var firstWeekday: Int {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month))!
        return Calendar.current.component(.weekday, from: date) - 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(month)月")
                .font(.system(size: 18, weight: isCurrentMonth ? .bold : .semibold))
                .foregroundColor(isCurrentMonth ? .red : .black)
            
            LazyVGrid(columns: columns, spacing: 3) {
                // 空白填充
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Color.clear.frame(height: 12)
                }
                // 日期
                ForEach(1...daysInMonth, id: \.self) { day in
                    let isToday = todayInfo.year == year && todayInfo.month == month && todayInfo.day == day
                    Text("\(day)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isToday ? .white : .black.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                        .background(isToday ? Circle().fill(Color.red) : nil)
                }
            }
        }
    }
}
