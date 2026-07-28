import { IsNumber, Max, Min } from 'class-validator';

export class CreateRechargeOrderDto {
  /** Rupees. Server rounds to whole rupees and re-validates. */
  @IsNumber()
  @Min(10)
  @Max(100000)
  amount: number;
}
