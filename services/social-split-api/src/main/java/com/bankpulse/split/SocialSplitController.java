package com.bankpulse.split;

import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.Duration;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/splits")
public class SocialSplitController {

    private final SplitSessionRepository repo;
    private final SocialSplitMetrics metrics;

    SocialSplitController(
        SplitSessionRepository repo,
        SocialSplitMetrics metrics
    ) {
        this.repo = repo;
        this.metrics = metrics;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    SplitSession create(
        @Valid @RequestBody CreateSplit r
    ) {

        SplitSession saved = repo.save(
            new SplitSession(
                r.hostMemberId(),
                r.totalAmount(),
                r.currency()
            )
        );

        metrics.sessionCreated();

        return saved;
    }

    @GetMapping("/{id}")
    SplitSession get(
        @PathVariable String id
    ) {
        return repo.findById(id)
            .orElseThrow();
    }

    @PostMapping("/{id}/participants")
    @Transactional
    SplitSession participant(
        @PathVariable String id,
        @Valid @RequestBody AddParticipant r
    ) {

        SplitSession s = get(id);

        s.addParticipant(
            r.memberId(),
            r.shareAmount()
        );

        SplitSession saved = repo.save(s);

        metrics.participantAdded();

        return saved;
    }

    @PostMapping("/{id}/participants/{participantId}/authorize")
    @Transactional
    SplitSession authorize(
        @PathVariable String id,
        @PathVariable String participantId,
        @Valid @RequestBody Authorize r
    ) {

        SplitSession s = get(id);

        SplitParticipant p = s.getParticipants()
            .stream()
            .filter(
                x -> x.getId().equals(participantId)
            )
            .findFirst()
            .orElseThrow();

        boolean wasAuthorized =
            p.isAuthorized();

        p.authorize(
            r.paymentReference()
        );

        SplitSession saved =
            repo.save(s);

        if (!wasAuthorized) {
            metrics.participantAuthorized();
        }

        return saved;
    }

    @PostMapping("/{id}/close")
    @Transactional
    SplitSession close(
        @PathVariable String id
    ) {

        SplitSession s = get(id);

        boolean wasCompleted =
            "COMPLETED".equals(
                s.getStatus()
            );

        metrics.closeAttempt();

        try {
            s.closeIfAuthorized();
        } catch (IllegalStateException e) {
            metrics.closeBlocked();
            throw e;
        }

        SplitSession saved =
            repo.save(s);

        if (
            !wasCompleted
            && "COMPLETED".equals(
                saved.getStatus()
            )
        ) {

            Duration duration =
                Duration.between(
                    saved.getCreatedAt(),
                    saved.getCompletedAt()
                );

            metrics.sessionCompleted(
                duration
            );

            if (
                saved.hasBalancedDistribution()
            ) {
                metrics.settlementValid();
            } else {
                metrics.settlementInvalid();
            }
        }

        return saved;
    }

    public record CreateSplit(
        @NotBlank
        String hostMemberId,

        @DecimalMin("0.01")
        BigDecimal totalAmount,

        @Pattern(regexp = "[A-Z]{3}")
        String currency
    ) {}

    public record AddParticipant(
        @NotBlank
        String memberId,

        @DecimalMin("0.01")
        BigDecimal shareAmount
    ) {}

    public record Authorize(
        @NotBlank
        String paymentReference
    ) {}
}