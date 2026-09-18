package com.bankpulse.split;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "split_sessions")
public class SplitSession {

    @Id
    private String id = UUID.randomUUID().toString();

    private String hostMemberId;
    private BigDecimal totalAmount;
    private String currency;
    private String status;
    private Instant createdAt;
    private Instant completedAt;

    @OneToMany(
        mappedBy = "session",
        cascade = CascadeType.ALL,
        orphanRemoval = true,
        fetch = FetchType.EAGER
    )
    private List<SplitParticipant> participants = new ArrayList<>();

    protected SplitSession() {}

    public SplitSession(
        String hostMemberId,
        BigDecimal totalAmount,
        String currency
    ) {
        this.hostMemberId = hostMemberId;
        this.totalAmount = totalAmount;
        this.currency = currency;
        this.status = "OPEN";
        this.createdAt = Instant.now();
    }

    public String getId() {
        return id;
    }

    public String getHostMemberId() {
        return hostMemberId;
    }

    public BigDecimal getTotalAmount() {
        return totalAmount;
    }

    public String getCurrency() {
        return currency;
    }

    public String getStatus() {
        return status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public List<SplitParticipant> getParticipants() {
        return participants;
    }

    public void addParticipant(
        String memberId,
        BigDecimal share
    ) {
        participants.add(
            new SplitParticipant(
                this,
                memberId,
                share
            )
        );
    }

    public void closeIfAuthorized() {

        if ("COMPLETED".equals(status)) {
            return;
        }

        if (
            participants.isEmpty()
            || participants.stream()
                .anyMatch(p -> !p.isAuthorized())
        ) {
            throw new IllegalStateException(
                "all participants must authorize"
            );
        }

        status = "COMPLETED";
        completedAt = Instant.now();
    }

    public boolean hasBalancedDistribution() {

        BigDecimal distributed = participants.stream()
            .map(SplitParticipant::getShareAmount)
            .reduce(
                BigDecimal.ZERO,
                BigDecimal::add
            );

        return distributed.compareTo(totalAmount) == 0;
    }
}