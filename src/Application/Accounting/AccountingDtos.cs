namespace MiniErp.Application.Accounting;

public sealed record ChartOfAccountDto(
    Guid Id,
    string Code,
    string Name,
    string? Description,
    int Level,
    Guid? ParentId,
    bool IsActive,
    DateTimeOffset CreatedAt,
    DateTimeOffset? UpdatedAt,
    string RowVersion);

public sealed record SaveChartOfAccountRequest(
    string Code,
    string Name,
    string? Description,
    Guid? ParentId,
    bool IsActive);

public sealed record JournalEntryDto(
    Guid Id,
    string JournalNumber,
    DateOnly EntryDate,
    List<JournalLineDto> Lines,
    decimal TotalDebits,
    decimal TotalCredits,
    string? Notes,
    DateTimeOffset CreatedAt,
    DateTimeOffset? PostedAt,
    string? PostedBy,
    string RowVersion);

public sealed record SaveJournalEntryRequest(
    string JournalNumber,
    DateOnly EntryDate,
    List<SaveJournalLineRequest> Lines,
    string? Notes);

public sealed record JournalLineDto(
    Guid Id,
    Guid AccountId,
    decimal DebitAmount,
    decimal CreditAmount,
    string Description,
    int LineNumber);

public sealed record SaveJournalLineRequest(
    Guid AccountId,
    decimal Amount,
    string Description);

public sealed record GLReportDto(
    Guid Id,
    string ReportName,
    string Description,
    DateOnly StartDate,
    DateOnly EndDate,
    List<GLLineDto> Lines,
    decimal TotalDebits,
    decimal TotalCredits,
    DateTimeOffset GeneratedAt);

public sealed record GLLineDto(
    Guid Id,
    string AccountCode,
    string AccountName,
    decimal Debit,
    decimal Credit,
    string Description);